//
//  FeaturePrints.swift
//  FlowerPower
//
//  The Vision half of placing a flower without a trained model.
//
//  `FeaturePrintLibrary`, in the package, holds the reference photographs and
//  does the nearest-neighbour arithmetic — and is tested, because that is the
//  part that can be quietly wrong. This file does the one thing that needs an
//  Apple platform: turning an image into a vector.
//
//  Written against the Swift Vision API rather than the older `VN` classes.
//  It is `async` throughout, so a feature print no longer needs a completion
//  handler or a request handler kept alive by hand.
//
//  On comparing prints
//  -------------------
//  Feature print length depends on which algorithm revision produced it, and
//  vectors from different revisions are not in the same space — a distance
//  between them is a number that means nothing. The revision is pinned rather
//  than left to the default, because Vision quietly choosing a newer one after
//  an OS update would put every new print in a different space from every
//  saved reference, and the library would stop matching anything without ever
//  erroring.
//
//  Reading the buffer as the wrong element type has the same shape of failure:
//  it does not throw, it produces plausible-looking nonsense, and it surfaces
//  much later as a classifier that is merely bad. So the type is checked
//  rather than assumed.
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

    /// Pinned. See the note above on why this is not left to the default.
    static let revision = GenerateImageFeaturePrintRequest.Revision.revision2

    /// Turns an image into a vector.
    static func print(
        for image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> FeaturePrint? {

        var request = GenerateImageFeaturePrintRequest()
        request.revision = revision
        // Flowers are the subject and usually centred. Squashing the whole
        // frame to a square would distort the thing being measured.
        request.cropAndScaleAction = .centerCrop

        do {
            let observation = try await request.perform(on: image, orientation: orientation)
            return vector(from: observation)
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }
    }

    /// Reads the observation's buffer according to the element type it
    /// actually carries.
    static func vector(from observation: FeaturePrintObservation) -> FeaturePrint? {
        let data = observation.data
        let count = observation.elementCount

        switch observation.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return nil }
            return FeaturePrint(data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self).prefix(count))
            })

        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return nil }
            return FeaturePrint(data.withUnsafeBytes { raw in
                raw.bindMemory(to: Double.self).prefix(count).map(Float.init)
            })

        @unknown default:
            // Including any element type a future revision introduces.
            // Guessing would produce a classifier that is confidently wrong
            // rather than one that is honestly quiet.
            logger.error("unsupported feature print element type")
            return nil
        }
    }

    /// Whether an image looks like plant material at all.
    ///
    /// The coarse gate that stops a photograph of a car door becoming a nectar
    /// patch. Vision's own taxonomy ships with the OS and needs no model.
    static func looksLikePlantMaterial(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        threshold: Float = 0.15
    ) async throws -> Bool {

        do {
            let observations = try await ClassifyImageRequest()
                .perform(on: image, orientation: orientation)

            return observations.contains { observation in
                observation.confidence >= threshold
                    && plantLabels.contains(observation.identifier.lowercased())
            }
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }
    }

    /// Vision taxonomy labels that count as plant material.
    private static let plantLabels: Set<String> = [
        "flower", "flowers", "plant", "plants", "blossom", "petal",
        "flowering_plant", "garden", "wildflower", "bud", "shrub",
        "tree", "herb", "foliage", "leaf", "botany"
    ]
}

// MARK: - Keeping the library

/// Where the reference photographs live between launches.
///
/// The library grows as the game is played: a player who places a flower
/// themselves has just labelled a photograph, and a flower somebody shares
/// arrives with a label and a picture. Both are worth keeping, so
/// identification gets better the more the game is used — which matters when
/// the alternative is shipping with none at all.
///
/// An actor rather than a lock. Learning a flower runs a Vision request and
/// then writes a file: both want to be off the main thread, and neither
/// should race the other. Under the Swift 6 language mode that is checked
/// rather than hoped for.
actor FeaturePrintStore {

    static let shared = FeaturePrintStore()

    private let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "featurePrints"
    )

    private var stored: FeaturePrintLibrary

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

    var library: FeaturePrintLibrary { stored }

    /// References shipped with the app, if any have been curated yet.
    ///
    /// There are none today, which is the honest state of things: building
    /// them means photographing the catalogue species, or embedding
    /// research-grade observations. Until then the library starts empty and
    /// fills from what the player places, so identification works from the
    /// first flower they name by hand rather than not at all.
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

    private func save() {
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
    func learn(
        _ image: CGImage,
        as species: FlowerSpecies,
        source: SpeciesReference.Source
    ) async {
        do {
            guard let print = try await FeaturePrints.print(for: image) else { return }
            stored.add(SpeciesReference(speciesID: species.id, print: print, source: source))
            save()
        } catch {
            logger.error("could not learn a flower: \(error.localizedDescription)")
        }
    }
}
