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
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "featurePrints"
    )

    /// Pinned. See the note above on why this is not left to the default.
    static let revision = GenerateImageFeaturePrintRequest.Revision.revision2

    /// Turns an image into a vector.
    static func print(
        for image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> FeaturePrint? {

        // The revision is fixed at construction; it is a `let` on the request.
        var request = GenerateImageFeaturePrintRequest(revision)
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

    /// What Vision's own classifier makes of an image: its labels, with
    /// confidences, lower-cased. The taxonomy ships with the OS and needs no
    /// model. Run once per photograph; both the plant gate and the label
    /// rung read the same answer.
    static func labels(
        for image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [(label: String, confidence: Float)] {
        do {
            let observations = try await ClassifyImageRequest()
                .perform(on: image, orientation: orientation)
            return observations.map { ($0.identifier.lowercased(), $0.confidence) }
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }
    }

    /// Whether the labels say plant material at all.
    ///
    /// The coarse gate that stops a photograph of a car door becoming a nectar
    /// patch.
    static func looksLikePlantMaterial(
        _ labels: [(label: String, confidence: Float)],
        threshold: Float = 0.15
    ) -> Bool {
        labels.contains { $0.confidence >= threshold && plantLabels.contains($0.label) }
    }

    /// Whether an image looks like plant material at all.
    static func looksLikePlantMaterial(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        threshold: Float = 0.15
    ) async throws -> Bool {
        looksLikePlantMaterial(try await labels(for: image, orientation: orientation), threshold: threshold)
    }

    /// The best flower Vision named outright, if it named one it is sure of.
    ///
    /// Vision's confidences are independent per label rather than a
    /// distribution, so the threshold is an absolute one: "tulip at 0.7"
    /// means Vision is fairly sure it is a tulip, whatever else it also
    /// thought.
    static func namedFlower(
        in labels: [(label: String, confidence: Float)],
        threshold: Float = 0.4
    ) -> (species: FlowerSpecies, confidence: Double)? {
        labels
            .filter { $0.confidence >= threshold && VisionLabelTaxa.knows($0.label) }
            .sorted { $0.confidence > $1.confidence }
            .lazy
            .compactMap { observation in
                VisionLabelTaxa.species(forLabel: observation.label)
                    .map { ($0, Double(observation.confidence)) }
            }
            .first
    }

    // MARK: - Where the flower is

    /// A square around whatever Vision thinks the subject is, in the pixel
    /// coordinates of `image`, or nil when that square would be the centre
    /// crop anyway.
    ///
    /// Every identifier here is handed the centre square of the frame, and
    /// a flower is usually there — but not always: a player photographing a
    /// bramble at arm's length puts the flower a third of the way up with a
    /// hedge round it, and the centre crop then shows mostly hedge. Vision's
    /// objectness saliency finds the thing in the picture without knowing
    /// what it is, which is the right tool for a model that then says what
    /// it is. The crop is padded, kept to at least a third of the short edge
    /// so a stray blob cannot zoom the model into a few hundred pixels of
    /// petal, and only used when it frames something the centre square does
    /// not. Only for upright pixels: the boxes come back in the oriented
    /// frame, and this crops the stored one.
    static func salientSquare(in image: CGImage) async -> CGRect? {
        let size = CGSize(width: image.width, height: image.height)
        guard let observation = try? await GenerateObjectnessBasedSaliencyImageRequest()
            .perform(on: image, orientation: .up)
        else { return nil }
        let boxes = observation.salientObjects.map {
            $0.boundingBox.toImageCoordinates(size, origin: .upperLeft)
        }
        return squareCrop(around: boxes, in: size)
    }

    /// The geometry of `salientSquare`, on its own so it can be tested
    /// without Vision.
    static func squareCrop(
        around boxes: [CGRect],
        in size: CGSize,
        padding: CGFloat = 0.12,
        smallest: CGFloat = 0.34,
        sameAsCentre: CGFloat = 0.9
    ) -> CGRect? {
        guard var union = boxes.first else { return nil }
        for box in boxes.dropFirst() { union = union.union(box) }
        guard union.width > 0, union.height > 0 else { return nil }

        let shortEdge = min(size.width, size.height)
        var side = max(union.width, union.height) * (1 + 2 * padding)
        side = min(max(side, shortEdge * smallest), shortEdge)
        // Near enough the whole short edge is the centre crop by another
        // route, and not worth a second pass through the model.
        guard side < shortEdge * sameAsCentre else { return nil }

        var origin = CGPoint(x: union.midX - side / 2, y: union.midY - side / 2)
        origin.x = min(max(0, origin.x), size.width - side)
        origin.y = min(max(0, origin.y), size.height - side)
        return CGRect(origin: origin, size: CGSize(width: side, height: side)).integral
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
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "featurePrints"
    )

    private var stored: FeaturePrintLibrary

    private static var url: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("flower-references.json")
    }

    /// Both halves are read before `stored` is set, because a synchronous
    /// actor initialiser is not isolated to the actor and may not call its
    /// methods. Nothing else can see the actor yet, so there is nothing to
    /// isolate from.
    init() {
        var library = Self.bundledLibrary()
        for reference in Self.learnedReferences() {
            library.add(reference)
        }
        stored = library
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

    private static func learnedReferences() -> [SpeciesReference] {
        guard
            let data = try? Data(contentsOf: url),
            let learned = try? JSONDecoder().decode([SpeciesReference].self, from: data)
        else { return [] }
        return learned
    }

    private func save() {
        // Only what was learned. The bundled half is in the app already, and
        // writing it out again would double it on every launch.
        let learned = stored.references.filter { $0.source != .bundled }

        do {
            try JSONEncoder().encode(learned).write(to: Self.url, options: .atomic)
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
