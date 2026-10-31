//
//  BioCLIPClassifier.swift
//  FlowerPower
//
//  Naming any flowering plant on Earth, on the phone.
//
//  BioCLIP 2 is an open model (Imageomics, MIT licence) trained on two
//  hundred million photographs of living things to put a picture and the
//  text of its taxonomic name in the same place. Only the picture half is on
//  the phone: a Core ML image encoder that turns a photograph into 768
//  numbers. The text half was run once, at build time, over every flowering
//  plant the model knows — some 42,000 species, every genus and every family
//  — and shipped as a matrix. Identifying a flower is one pass through the
//  encoder and one pass down the matrix, and the arithmetic of the second
//  pass is `TaxonEmbeddingIndex` in the package, where it is tested.
//
//  The model is about 300 MB and built rather than checked in; see
//  `tools/bioclip/build.py`. A build without it is still a working app —
//  `bundled()` returns nil and `FlowerClassifier` falls through to the rungs
//  below — because that is the design decision the whole feature rests on.
//

import Foundation
import CoreML
import Vision
import CoreGraphics
import ImageIO
import os
import FlowerPowerCore

struct BioCLIPClassifier: Sendable {

    /// The image encoder. `VNCoreMLModel` is not declared `Sendable`; it is
    /// loaded once, never mutated, and handed to one request at a time.
    nonisolated(unsafe) private let model: VNCoreMLModel
    let index: TaxonEmbeddingIndex

    private static let logger = Logger(
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "bioclip"
    )

    init(model: VNCoreMLModel, index: TaxonEmbeddingIndex) {
        self.model = model
        self.index = index
    }

    // MARK: - Loading

    /// The identifier, if the model was built into this app.
    ///
    /// Loading 300 MB of weights takes a moment and is done here, off the
    /// main thread, once — `FlowerClassifier.bundled()` is already awaited
    /// when the capture screen opens, so the wait overlaps the player
    /// framing the shot.
    static func bundled() async -> BioCLIPClassifier? {
        guard let index = await TaxonIndexStore.shared.index else { return nil }

        guard let url = Bundle.main.url(forResource: "BioCLIP2", withExtension: "mlmodelc") else {
            logger.info("no BioCLIP2 model in the bundle; see tools/bioclip")
            return nil
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let coreML = try await MLModel.load(contentsOf: url, configuration: configuration)
            let model = try VNCoreMLModel(for: coreML)
            return BioCLIPClassifier(model: model, index: index)
        } catch {
            logger.error("BioCLIP2 failed to load: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Identifying

    /// The photograph as the model sees it: a unit vector in its shared
    /// image-text space.
    func embedding(
        for image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> [Float] {
        let request = VNCoreMLRequest(model: model)
        // The flower is the subject and usually centred; the model was
        // trained on square crops.
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw FlowerClassifierError.visionFailed(underlying: error)
        }

        guard
            let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
            let array = observation.featureValue.multiArrayValue
        else { return [] }

        let count = array.count
        var vector = [Float](repeating: 0, count: count)
        for i in 0..<count {
            vector[i] = array[i].floatValue
        }
        return vector
    }

    /// Places a photograph as precisely as the model honestly can.
    func place(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> TaxonEmbeddingIndex.Placement? {
        let vector = try embedding(for: image, orientation: orientation)
        guard !vector.isEmpty else { return nil }
        let placement = index.place(vector)

        if let placement {
            Self.logger.info("""
                bioclip: species \(placement.bestSpecies?.entry.scientificName ?? "-") \
                \(placement.bestSpecies?.probability ?? 0, format: .fixed(precision: 2)), \
                genus \(placement.bestGenus?.entry.scientificName ?? "-") \
                \(placement.bestGenus?.probability ?? 0, format: .fixed(precision: 2)), \
                family \(placement.bestFamily?.entry.scientificName ?? "-") \
                \(placement.bestFamily?.probability ?? 0, format: .fixed(precision: 2))
                """)
        }
        return placement
    }
}

// MARK: - The names

/// The taxon matrix, loaded once and shared.
///
/// Two things need it: the classifier, to place photographs, and the
/// picker, so a player naming a flower themselves can name any flower and
/// not only the thirty in the catalogue. It is 44 MB and takes a moment to
/// parse, so it is read once, off the main thread, and kept.
actor TaxonIndexStore {

    static let shared = TaxonIndexStore()

    private var loaded: TaxonEmbeddingIndex?
    private var attempted = false

    private let logger = Logger(
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "bioclip"
    )

    var index: TaxonEmbeddingIndex? {
        if !attempted {
            attempted = true
            loaded = load()
        }
        return loaded
    }

    private func load() -> TaxonEmbeddingIndex? {
        guard
            let matrixURL = Bundle.main.url(forResource: "BioCLIPTaxa", withExtension: "bin"),
            let namesURL = Bundle.main.url(forResource: "BioCLIPTaxa", withExtension: "json")
        else {
            logger.info("no taxon index in the bundle; see tools/bioclip")
            return nil
        }
        do {
            let matrix = try Data(contentsOf: matrixURL, options: .mappedIfSafe)
            let names = try Data(contentsOf: namesURL)
            let index = try TaxonEmbeddingIndex(matrix: matrix, names: names)
            logger.info("taxon index: \(index.entries.count) names")
            return index
        } catch {
            logger.error("taxon index failed to load: \(error.localizedDescription)")
            return nil
        }
    }
}
