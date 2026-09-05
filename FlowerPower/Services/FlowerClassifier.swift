//
//  FlowerClassifier.swift
//  FlowerPower
//
//  Turning a photograph into forage.
//
//  Two stages, because they answer different questions and fail differently:
//
//  1. Vision's built-in classifier asks "is this a flower at all?". It ships
//     with the OS, needs no model, and is reliable at that coarse level. It is
//     what stops a photo of a car door becoming a nectar patch.
//
//  2. A Core ML model asks "which flower?". This is the part that needs
//     training — Create ML over a flower dataset such as Oxford 102 — and it is
//     the part that will sometimes be wrong.
//
//  The important design decision is that stage 2 is optional. An unrecognised
//  flower still feeds the colony at a reduced yield, so a blurry photo costs
//  the player some reward rather than breaking the loop. Ship without a model
//  and the game still works; add one and identification becomes a bonus.
//
//  Note on Visual Look Up: the plant identification in Photos is not available
//  to third-party apps through any public API. It cannot be used here.
//

import Foundation
import Vision
import CoreML
import CoreImage
import ImageIO
import os
import FlowerPowerCore

// MARK: - Result

public struct FlowerIdentification: Equatable, Sendable {

    /// `nil` when the model could not place it, or when no model is bundled.
    public let species: FlowerSpecies?
    /// 0...1 for the species call.
    public let confidence: Double
    /// Whether the image looks like a flower or plant at all.
    public let looksLikeAFlower: Bool
    /// Runner-up guesses, best first, for a "did you mean?" affordance.
    public let alternatives: [Alternative]

    public struct Alternative: Equatable, Sendable {
        public let species: FlowerSpecies
        public let confidence: Double
    }

    /// Nothing recognisable in the frame.
    public static let notAFlower = FlowerIdentification(
        species: nil, confidence: 0, looksLikeAFlower: false, alternatives: []
    )

    /// A flower, but an unidentified one. Still perfectly playable.
    public static let unidentifiedFlower = FlowerIdentification(
        species: nil, confidence: 0, looksLikeAFlower: true, alternatives: []
    )
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
    func identify(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> FlowerIdentification
}

// MARK: - Classifier

public final class FlowerClassifier: FlowerIdentifying {

    /// Minimum Vision confidence for "there is a plant in this photo".
    public static let plantGateThreshold: Float = 0.15
    /// Minimum species confidence before we claim an identification.
    public static let speciesThreshold: Double = 0.25

    /// Vision taxonomy labels that count as plant material.
    private static let plantLabels: Set<String> = [
        "flower", "flowers", "plant", "plants", "blossom", "petal",
        "flowering_plant", "garden", "wildflower", "bud", "shrub",
        "tree", "herb", "foliage", "leaf", "botany"
    ]

    private let model: VNCoreMLModel?
    private let logger = Logger(subsystem: "com.kylepeterson.flowerpower", category: "classifier")

    /// - Parameter model: a compiled Core ML flower classifier. Pass `nil` — the
    ///   default — to run with the plant gate only, which is the shipping
    ///   configuration until a model has been trained.
    public init(model: VNCoreMLModel? = nil) {
        self.model = model
    }

    /// Loads `FlowerClassifier.mlmodelc` from the bundle if it is there.
    public static func bundled(named name: String = "FlowerClassifier") -> FlowerClassifier {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            return FlowerClassifier(model: nil)
        }

        do {
            let coreML = try MLModel(contentsOf: url)
            return FlowerClassifier(model: try VNCoreMLModel(for: coreML))
        } catch {
            // A missing or broken model degrades identification, never the game.
            return FlowerClassifier(model: nil)
        }
    }

    public func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> FlowerIdentification {

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])

        // Stage one: is this plant material?
        let looksLikeAFlower = try classifyAsPlant(handler)
        guard looksLikeAFlower else { return .notAFlower }

        // Stage two: which plant? Optional.
        guard let model else { return .unidentifiedFlower }

        let matches = try classifySpecies(handler, model: model)
        guard let best = matches.first, best.confidence >= Self.speciesThreshold else {
            return .unidentifiedFlower
        }

        return FlowerIdentification(
            species: best.species,
            confidence: best.confidence,
            looksLikeAFlower: true,
            alternatives: Array(matches.dropFirst().prefix(3))
        )
    }

    // MARK: - Stages

    private func classifyAsPlant(_ handler: VNImageRequestHandler) throws -> Bool {
        let request = VNClassifyImageRequest()

        do {
            try handler.perform([request])
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }

        guard let observations = request.results else { return false }

        return observations.contains { observation in
            observation.confidence >= Self.plantGateThreshold
                && Self.plantLabels.contains(observation.identifier.lowercased())
        }
    }

    private func classifySpecies(
        _ handler: VNImageRequestHandler,
        model: VNCoreMLModel
    ) throws -> [FlowerIdentification.Alternative] {

        let request = VNCoreMLRequest(model: model)
        // Flowers are usually the subject and centred; cropping to the centre
        // square beats squashing the whole frame.
        request.imageCropAndScaleOption = .centerCrop

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
/// be tested without a camera or a model.
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
