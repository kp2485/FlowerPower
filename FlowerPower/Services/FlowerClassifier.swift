//
//  FlowerClassifier.swift
//  FlowerPower
//
//  Turning a photograph into forage.
//
//  Two questions, answered separately because they fail differently.
//
//  1. Is this a plant at all? Vision's built-in classifier ships with the OS,
//     needs no model, and is reliable at that coarse level. It is what stops a
//     photograph of a car door becoming a nectar patch.
//
//  2. *What* plant, and how precisely can that honestly be said? Four ways to
//     answer, tried best first:
//
//     BioCLIP 2, through `BioCLIPClassifier`: an open model that knows every
//     flowering plant on Earth, bundled as a Core ML image encoder and a
//     matrix of taxon names. Places to species, genus or family and says
//     which. Needs the model to have been built (tools/bioclip).
//
//     Vision's own labels. The classifier that ships with the OS knows a
//     couple of dozen well-known flowers by name — rose, tulip, orchid,
//     daffodil — and this rung keeps what the plant gate already asked it.
//
//     The on-device language model, through `TaxonomicClassifier`. Can name
//     a family, genus or species from the photograph. Needs Apple
//     Intelligence.
//
//     Otherwise nearest-neighbour matching against reference photographs using
//     Vision feature prints. No model, no dataset; works on every device.
//
//  Every rung down places fewer flowers, and none of them stops the game,
//  because an unplaced flower still feeds the colony. That is the design
//  decision the whole feature rests on: identification is a bonus, never a
//  gate, so a classifier that is right much of the time and honest about the
//  rest is worth having.
//

import Foundation
import Vision
import CoreML
import CoreImage
import ImageIO
import UIKit
import os
import FlowerPowerCore

// MARK: - Result

public struct FlowerIdentification: Equatable, Sendable {

    /// What the flower is, at whatever rank could honestly be reached, or
    /// `nil` when it could not be placed at all.
    ///
    /// A family is a real answer rather than a failed species: floral
    /// architecture is largely conserved by family, so knowing a plant is a
    /// borage tells the game most of what governs whether a honey bee can work
    /// it.
    public let taxon: Taxon?

    /// The forage description that follows from `taxon` — a catalogue entry
    /// when the plant was placed to a species the game knows, and the family's
    /// or genus's typical traits otherwise.
    public let species: FlowerSpecies?

    /// 0...1 for the placement at `taxon.rank`.
    public let confidence: Double
    /// Whether the image looks like a flower or plant at all.
    public let looksLikeAFlower: Bool
    /// Runner-up guesses, best first, for a "did you mean?" affordance.
    public let alternatives: [Alternative]

    public struct Alternative: Equatable, Sendable {
        public let species: FlowerSpecies
        public let confidence: Double
    }

    public init(
        taxon: Taxon? = nil,
        species: FlowerSpecies?,
        confidence: Double,
        looksLikeAFlower: Bool,
        alternatives: [Alternative]
    ) {
        self.taxon = taxon
        self.species = species
        self.confidence = confidence
        self.looksLikeAFlower = looksLikeAFlower
        self.alternatives = alternatives
    }

    /// How precisely the plant was placed, when it was placed at all.
    public var rank: TaxonomicRank? { taxon?.rank }

    /// Nothing recognisable in the frame.
    public static let notAFlower = FlowerIdentification(
        species: nil, confidence: 0, looksLikeAFlower: false, alternatives: []
    )

    /// A flower, but one nothing could place. Still perfectly playable.
    public static let unplacedFlower = FlowerIdentification(
        species: nil, confidence: 0, looksLikeAFlower: true, alternatives: []
    )

    @available(*, deprecated, renamed: "unplacedFlower")
    public static var unidentifiedFlower: FlowerIdentification { unplacedFlower }
}

public enum FlowerClassifierError: Error, LocalizedError {
    case couldNotReadImage
    case visionFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .couldNotReadImage: return "That image could not be read."
        case .visionFailed(let error): return "Identification failed: \(error.localizedDescription)"
        }
    }
}

public protocol FlowerIdentifying: Sendable {
    func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> FlowerIdentification
}

// MARK: - Classifier

public struct FlowerClassifier: FlowerIdentifying {

    /// Minimum confidence before a placement is claimed at all.
    public static let placementThreshold: Double = 0.25

    private let bioCLIP: BioCLIPClassifier?
    private let library: FeaturePrintLibrary?
    private let onDevice: TaxonomicClassifier?
    private let logger = Logger(subsystem: "com.linwoodtechnologies.flowerpower", category: "classifier")

    /// Internal, not public, because `TaxonomicClassifier` is. Nothing outside
    /// the app module could call it anyway.
    init(
        bioCLIP: BioCLIPClassifier? = nil,
        library: FeaturePrintLibrary? = nil,
        onDevice: TaxonomicClassifier? = nil
    ) {
        self.bioCLIP = bioCLIP
        self.library = library
        self.onDevice = onDevice
    }

    /// The best identifier available on this device right now.
    public static func bundled() async -> FlowerClassifier {
        async let bioCLIP = BioCLIPClassifier.bundled()
        async let library = FeaturePrintStore.shared.library
        let onDevice = TaxonomicClassifier.isAvailable ? TaxonomicClassifier() : nil
        return await FlowerClassifier(bioCLIP: bioCLIP, library: library, onDevice: onDevice)
    }

    public func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> FlowerIdentification {

        // Stage one: is this plant material? Vision is asked once; the
        // answer is kept, because its labels are also the second rung.
        let labels = try await FeaturePrints.labels(for: image, orientation: orientation)
        guard FeaturePrints.looksLikePlantMaterial(labels) else { return .notAFlower }

        // Stage two, best available answer first.

        // BioCLIP 2: any flowering plant, to whatever rank it is sure of.
        if let bioCLIP {
            do {
                if let placement = try bioCLIP.place(image, orientation: orientation),
                   let taxon = placement.taxon {
                    return identification(
                        for: taxon,
                        confidence: placement.confidence,
                        commonName: placement.commonName,
                        runnersUp: placement.alternatives.map {
                            ($0.entry.taxon, Double($0.probability), $0.entry.commonName)
                        }
                    )
                }
            } catch {
                // A model that fails on one image degrades that placement,
                // never the game. The rungs below still run.
                logger.error("bioclip failed: \(error.localizedDescription)")
            }
        }

        // Vision named the flower outright.
        if let named = FeaturePrints.namedFlower(in: labels) {
            return identification(
                for: named.species.taxon, confidence: named.confidence, known: named.species
            )
        }

        // The on-device language model.
        if let onDevice, let placement = try? await onDevice.place(UIImage(cgImage: image)),
           placement.confidence >= Self.placementThreshold {
            return identification(for: placement.taxon, confidence: placement.confidence)
        }

        // Reference photographs the player has labelled.
        if let library, !library.isEmpty {
            let matches = try await matchAgainstReferences(
                image, orientation: orientation, library: library
            )
            if let best = matches.first, best.confidence >= Self.placementThreshold {
                return FlowerIdentification(
                    taxon: best.species.taxon,
                    species: best.species,
                    confidence: best.confidence,
                    looksLikeAFlower: true,
                    alternatives: Array(matches.dropFirst().prefix(3))
                )
            }
        }

        return .unplacedFlower
    }

    // MARK: - Stages

    /// Builds a result from a placement at any rank.
    ///
    /// A species the catalogue knows becomes that catalogue entry. Anything
    /// coarser, or any plant the catalogue has never heard of, becomes the
    /// family's or genus's typical forage, which is a real description rather
    /// than a fallback. `commonName` is what the identifier called it, and
    /// `runnersUp` are its other guesses at the same rank.
    private func identification(
        for taxon: Taxon,
        confidence: Double,
        commonName: String? = nil,
        known: FlowerSpecies? = nil,
        runnersUp: [(taxon: Taxon, confidence: Double, commonName: String)] = []
    ) -> FlowerIdentification {

        let catalogued = known ?? FlowerCatalogue.all.first { $0.taxon == taxon }
        let species = catalogued ?? FlowerSpecies.generic(for: taxon, commonName: commonName)

        // The identifier's own runners-up first, then members of the same
        // group the catalogue knows about, so a player can sharpen a family
        // into a species. Capped so the card does not become a list.
        var alternatives: [FlowerIdentification.Alternative] = runnersUp.prefix(3).map { guess in
            let match = FlowerCatalogue.all.first { $0.taxon == guess.taxon }
            return FlowerIdentification.Alternative(
                species: match ?? FlowerSpecies.generic(for: guess.taxon, commonName: guess.commonName),
                confidence: guess.confidence
            )
        }
        let relatives = FlowerCatalogue.all
            .filter { taxon.contains($0.taxon) && $0.id != species.id }
            .prefix(3)
            .map { FlowerIdentification.Alternative(species: $0, confidence: confidence * 0.5) }
        for relative in relatives where !alternatives.contains(where: { $0.species.id == relative.species.id }) {
            alternatives.append(relative)
        }

        return FlowerIdentification(
            taxon: taxon,
            species: species,
            confidence: confidence,
            looksLikeAFlower: true,
            alternatives: Array(alternatives.prefix(4))
        )
    }

    /// Nearest neighbour against the reference photographs.
    private func matchAgainstReferences(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        library: FeaturePrintLibrary
    ) async throws -> [FlowerIdentification.Alternative] {

        guard let print = try await FeaturePrints.print(for: image, orientation: orientation)
        else { return [] }

        return library.identifications(for: print).map {
            FlowerIdentification.Alternative(species: $0.species, confidence: $0.confidence)
        }
    }
}

// MARK: - Test double

/// Returns whatever it is told to, so the capture flow and the game logic can
/// be tested without a camera, a model or Apple Intelligence.
public struct StubFlowerClassifier: FlowerIdentifying {

    private let result: FlowerIdentification

    public init(returning result: FlowerIdentification) {
        self.result = result
    }

    public func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> FlowerIdentification {
        result
    }
}
