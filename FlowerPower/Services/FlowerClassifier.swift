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
//  2. *What* plant, and how precisely can that honestly be said? Three ways to
//     answer, tried best first:
//
//     The on-device model, through `TaxonomicClassifier`. It can place a
//     flower to a family, a genus or a species and say which, which is the
//     shape the game wants. Needs Apple Intelligence.
//
//     A trained Core ML model, if one has been bundled. See
//     docs/CLASSIFIER.md, which also explains why Oxford 102 is the wrong
//     dataset for a catalogue of British bee forage.
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

    /// `VNCoreMLModel` is a class the SDK does not declare `Sendable`, and
    /// `FlowerIdentifying` requires this type to be. Unsafe by declaration
    /// rather than by omission: the model is loaded once, never mutated, and
    /// Vision is documented as safe to hand one request handler at a time,
    /// which is all `classifySpecies` does.
    nonisolated(unsafe) private let model: VNCoreMLModel?
    private let library: FeaturePrintLibrary?
    private let onDevice: TaxonomicClassifier?
    private let logger = Logger(subsystem: "com.kylepeterson.flowerpower", category: "classifier")

    public init(
        model: VNCoreMLModel? = nil,
        library: FeaturePrintLibrary? = nil,
        onDevice: TaxonomicClassifier? = nil
    ) {
        self.model = model
        self.library = library
        self.onDevice = onDevice
    }

    /// The best identifier available on this device right now.
    public static func bundled(named name: String = "FlowerClassifier") async -> FlowerClassifier {
        let library = await FeaturePrintStore.shared.library
        let onDevice = TaxonomicClassifier.isAvailable ? TaxonomicClassifier() : nil

        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            return FlowerClassifier(model: nil, library: library, onDevice: onDevice)
        }

        do {
            let coreML = try MLModel(contentsOf: url)
            return FlowerClassifier(
                model: try VNCoreMLModel(for: coreML),
                library: library,
                onDevice: onDevice
            )
        } catch {
            // A missing or broken model degrades placement, never the game.
            return FlowerClassifier(model: nil, library: library, onDevice: onDevice)
        }
    }

    public func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> FlowerIdentification {

        // Stage one: is this plant material?
        guard try await FeaturePrints.looksLikePlantMaterial(image, orientation: orientation)
        else { return .notAFlower }

        // Stage two, best available answer first.
        if let onDevice, let placed = try? await onDevice.place(UIImage(cgImage: image)),
           let placement = placed, placement.confidence >= Self.placementThreshold {
            return identification(for: placement.taxon, confidence: placement.confidence)
        }

        let matches: [FlowerIdentification.Alternative]
        if let model {
            matches = try await classifySpecies(image, orientation: orientation, model: model)
        } else if let library, !library.isEmpty {
            matches = try await matchAgainstReferences(
                image, orientation: orientation, library: library
            )
        } else {
            return .unplacedFlower
        }

        guard let best = matches.first, best.confidence >= Self.placementThreshold else {
            return .unplacedFlower
        }

        return FlowerIdentification(
            taxon: best.species.taxon,
            species: best.species,
            confidence: best.confidence,
            looksLikeAFlower: true,
            alternatives: Array(matches.dropFirst().prefix(3))
        )
    }

    // MARK: - Stages

    /// Builds a result from a placement at any rank.
    ///
    /// A species the catalogue knows becomes that catalogue entry. Anything
    /// coarser becomes the family's or genus's typical forage, which is a real
    /// description rather than a fallback.
    private func identification(
        for taxon: Taxon,
        confidence: Double
    ) -> FlowerIdentification {

        let known = FlowerCatalogue.all.first { $0.taxon == taxon }
        let species = known ?? FlowerSpecies.generic(for: taxon)

        // Members of the same group the catalogue knows about, offered as
        // "did you mean?" so a player can sharpen a family into a species.
        let relatives = FlowerCatalogue.all
            .filter { taxon.contains($0.taxon) && $0.id != species.id }
            .prefix(3)
            .map { FlowerIdentification.Alternative(species: $0, confidence: confidence * 0.5) }

        return FlowerIdentification(
            taxon: taxon,
            species: species,
            confidence: confidence,
            looksLikeAFlower: true,
            alternatives: Array(relatives)
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

    private func classifySpecies(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        model: VNCoreMLModel
    ) async throws -> [FlowerIdentification.Alternative] {

        let request = VNCoreMLRequest(model: model)
        // Flowers are usually the subject and centred; cropping to the centre
        // square beats squashing the whole frame.
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }

        guard let observations = request.results as? [VNClassificationObservation] else {
            return []
        }

        return observations
            .compactMap { observation in
                guard let species = FlowerCatalogue.match(label: observation.identifier) else {
                    return nil
                }
                return FlowerIdentification.Alternative(
                    species: species,
                    confidence: Double(observation.confidence)
                )
            }
            .sorted { $0.confidence > $1.confidence }
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
