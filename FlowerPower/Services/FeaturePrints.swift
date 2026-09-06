//
//  FeaturePrints.swift
//  FlowerPower
//
//  The Vision half of identifying a flower without a trained model.
//
//  `FeaturePrintLibrary`, in the package, holds the reference photographs and
//  does the nearest-neighbour arithmetic — and is tested, because that is the
//  part that can be quietly wrong. This file does the one thing that needs an
//  Apple platform: turning an image into a vector.
//
//  On reading the vector out
//  -------------------------
//  `VNFeaturePrintObservation` hands back raw bytes plus an element type,
//  and the type is not the same across Vision revisions — revision 1 is
//  32-bit floats, later ones may be 16-bit. Reading the buffer as the wrong
//  type does not fail, it produces plausible-looking nonsense, and the failure
//  would surface as a classifier that is simply bad rather than as an error.
//  So the element type is checked rather than assumed, and an unfamiliar one
//  returns nothing.
//
//  The same applies to comparing prints from different revisions: the vectors
//  are not in the same space and the distance between them is meaningless.
//  `FeaturePrint.distance(to:)` refuses when the lengths differ, which catches
//  the common case, and the stored revision below catches the rest.
//

import Foundation
import Vision
import CoreGraphics
import ImageIO
import FlowerPowerCore
import os

enum FeaturePrints {

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "featurePrints"
    )

    /// Which Vision revision the stored library was built with.
    ///
    /// Pinned rather than left to the default. Vision picking a newer revision
    /// after an OS update would put new prints in a different space from every
    /// reference already saved, and the whole library would silently stop
    /// matching anything.
    static let revision = VNGenerateImageFeaturePrintRequestRevision1

    /// Turns an image into a vector.
    static func print(
        for image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> FeaturePrint? {

        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        // Flowers are the subject and usually centred. Squashing the whole
        // frame to a square would distort the thing being measured.
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }

        return vector(from: observation)
    }

    /// Reads the observation's buffer according to the element type it
    /// actually carries.
    static func vector(from observation: VNFeaturePrintObservation) -> FeaturePrint? {
        let data = observation.data
        let count = observation.elementCount

        switch observation.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return nil }
            let values = data.withUnsafeBytes { raw -> [Float] in
                Array(raw.bindMemory(to: Float.self).prefix(count))
            }
            return FeaturePrint(values)

        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return nil }
            let values = data.withUnsafeBytes { raw -> [Float] in
                raw.bindMemory(to: Double.self).prefix(count).map(Float.init)
            }
            return FeaturePrint(values)

        default:
            // Including `.unknown`, and including any element type a future
            // Vision revision introduces. Guessing here would produce a
            // classifier that is confidently wrong rather than one that is
            // honestly quiet.
            logger.error(
                "unsupported feature print element type: \(observation.elementType.rawValue)"
            )
            return nil
        }
    }
}

// MARK: - Keeping the library

/// Where the reference photographs live between launches.
///
/// The library grows as the game is played: a player who names a flower
/// themselves has just labelled a photograph, and a flower somebody shares
/// arrives with a label and a picture. Both are worth keeping, so the thing
/// gets better the more the game is used — which matters a great deal when
/// the alternative is shipping with no identification at all.
///
/// Lock-protected rather than main-actor-isolated, because the classifier
/// reads it while being built and learning happens off the main thread after a
/// capture. Confining it to the main actor would push that isolation into
/// every caller for no benefit.
final class FeaturePrintStore: @unchecked Sendable {

    static let shared = FeaturePrintStore()

    private let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "featurePrints"
    )

    private let lock = NSLock()
    private var stored: FeaturePrintLibrary

    var library: FeaturePrintLibrary {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    private var url: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("flower-references.json")
    }

    init() {
        stored = Self.bundledLibrary()
        loadLearned()
    }

    /// References shipped with the app, if any have been curated yet.
    ///
    /// There are none today, which is the honest state of things: building
    /// them means photographing the thirty catalogue species, or pulling
    /// research-grade observations and embedding them. Until then the library
    /// starts empty and fills from what the player names, so the feature works
    /// from the first flower they identify by hand rather than not at all.
    private static func bundledLibrary() -> FeaturePrintLibrary {
        guard
            let url = Bundle.main.url(forResource: "FlowerReferences", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FeaturePrintLibrary.self, from: data)
        else {
            return FeaturePrintLibrary()
        }
        return decoded
    }

    private func loadLearned() {
        guard
            let data = try? Data(contentsOf: url),
            let learned = try? JSONDecoder().decode([SpeciesReference].self, from: data)
        else { return }

        for reference in learned {
            stored.add(reference)
        }
    }

    /// Caller holds the lock.
    private func saveLocked() {
        // Only what was learned. The bundled half is in the app already, and
        // writing it out again would double it on every launch.
        let learned = stored.references.filter { $0.source != .bundled }

        do {
            try JSONEncoder().encode(learned).write(to: url, options: .atomic)
        } catch {
            logger.error("could not keep flower references: \(error.localizedDescription)")
        }
    }

    /// Records that this image is this species.
    ///
    /// The feature print is computed outside the lock: it is the slow part,
    /// and holding a lock across Vision work would stall anything else that
    /// wanted to read the library.
    func learn(_ image: CGImage, as species: FlowerSpecies, source: SpeciesReference.Source) {
        let print: FeaturePrint?
        do {
            print = try FeaturePrints.print(for: image)
        } catch {
            logger.error("could not learn a flower: \(error.localizedDescription)")
            return
        }
        guard let print else { return }

        lock.lock(); defer { lock.unlock() }
        stored.add(SpeciesReference(speciesID: species.id, print: print, source: source))
        saveLocked()
    }
}
