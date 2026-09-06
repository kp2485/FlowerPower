//
//  TaxonomicClassifier.swift
//  FlowerPower
//
//  Placing a flower with the on-device model.
//
//  The Foundation Models framework gained image attachments in iOS 27, so the
//  model that ships with the system can now be handed a photograph and asked
//  about it. That is a good fit for this problem in a way a general image
//  classifier is not, because of one property: guided generation.
//
//  `@Generable` turns a Swift type into a schema the model is constrained to
//  fill in. So rather than asking "what flower is this?" and parsing prose,
//  the question is a form with a family, a genus, an epithet and a confidence,
//  and any of the finer fields may be left blank. That is exactly how
//  identifying a plant actually works — a photograph may plainly be a
//  member of the daisy family without being placeable to a species, and being
//  *told* that is far more useful than being given a confident guess at a
//  species it might not be.
//
//  Getting it wrong is worse than saying nothing. A patch identified as the
//  wrong species is given the wrong corolla depth, the wrong nectar and the
//  wrong bloom season, and the player is told something plainly false about
//  the world. So the prompt asks for the rank the model is sure of, and the
//  result is refused unless it is coherent.
//
//  This cannot be the only path. Apple Intelligence is not on every device,
//  and a model can be unavailable because the hardware is not eligible, the
//  feature is switched off, or the assets are still downloading.
//  `FlowerClassifier` treats this as the best of several rungs and falls
//  through to feature-print matching, which works everywhere.
//

import Foundation
import FoundationModels
import CoreGraphics
import UIKit
import FlowerPowerCore
import os

// MARK: - The shape of an answer

/// A plant family the on-device model may choose from.
///
/// A mirror of `PlantFamily` rather than the engine's own type: the engine is
/// built on Windows too and cannot import FoundationModels. Keeping the
/// vocabulary closed is the point — the model picks from the families the game
/// actually models rather than inventing one, and `PlantFamilyTests` fails if
/// the two lists drift apart.
@Generable
enum GenerableFamily: String, CaseIterable {
    case asteraceae, fabaceae, rosaceae, brassicaceae, boraginaceae
    case lamiaceae, ericaceae, salicaceae, araliaceae, malvaceae
    case papaveraceae, plantaginaceae, balsaminaceae, berberidaceae
    case crassulaceae, iridaceae, asparagaceae, apiaceae

    var family: PlantFamily? { PlantFamily(rawValue: rawValue) }
}

/// What the model is asked to fill in.
@Generable
struct FlowerAssessment {

    @Guide(description: "True only if the photograph clearly shows a flowering plant.")
    var isFloweringPlant: Bool

    @Guide(description: """
        The botanical family, chosen only if the flower's structure clearly \
        indicates it. Leave empty when unsure.
        """)
    var family: GenerableFamily?

    @Guide(description: """
        The genus, capitalised, such as Trifolium or Salix. Leave empty unless \
        the photograph clearly shows which genus it is. It is much better to \
        leave this out than to guess.
        """)
    var genus: String?

    @Guide(description: """
        The specific epithet in lower case, such as repens or caprea. Leave \
        empty unless the species is unmistakable. Most photographs cannot be \
        placed this precisely and should leave this out.
        """)
    var specificEpithet: String?

    @Guide(
        description: "Confidence in the finest rank given above.",
        .range(0...1)
    )
    var confidence: Double
}

// MARK: - The classifier

struct TaxonomicClassifier {

    private let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "taxonomy"
    )

    /// Why the on-device model cannot be used, when it cannot.
    enum Unavailable: Error, LocalizedError {
        case deviceNotEligible
        case appleIntelligenceOff
        case modelStillDownloading
        case other

        var errorDescription: String? {
            switch self {
            case .deviceNotEligible:
                return "This device cannot run on-device identification."
            case .appleIntelligenceOff:
                return "Turn on Apple Intelligence to have flowers placed for you."
            case .modelStillDownloading:
                return "The on-device model is still downloading."
            case .other:
                return "On-device identification is unavailable."
            }
        }
    }

    /// Whether the model can be used right now, and why not if it cannot.
    static var availability: Result<Void, Unavailable> {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .success(())
        case .unavailable(.deviceNotEligible):
            return .failure(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failure(.appleIntelligenceOff)
        case .unavailable(.modelNotReady):
            return .failure(.modelStillDownloading)
        case .unavailable:
            return .failure(.other)
        }
    }

    static var isAvailable: Bool {
        if case .success = availability { return true }
        return false
    }

    /// Places a photograph as precisely as the model can honestly manage.
    ///
    /// Returns `nil` when the picture is not a flower, or when the model
    /// cannot place it even to a family — both of which are real answers. A
    /// flower nobody can name still feeds the colony.
    func place(
        _ image: UIImage
    ) async throws -> (taxon: Taxon, confidence: Double)? {

        if case .failure(let reason) = Self.availability { throw reason }

        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(generating: FlowerAssessment.self) {
            """
            Identify the plant in this photograph as precisely as you can be \
            certain of, and no more precisely than that.
            """
            Attachment(image)
        }

        return taxon(from: response.content)
    }

    /// Turns an answer into a placement, refusing anything incoherent.
    ///
    /// Everything here is a way the model can be wrong in a way that would
    /// hand the colony a flower it is not: a species epithet with no genus, a
    /// genus that plainly does not belong to the family it was given, a
    /// confident placement of a photograph that is not a plant.
    func taxon(from assessment: FlowerAssessment) -> (taxon: Taxon, confidence: Double)? {
        guard assessment.isFloweringPlant else { return nil }
        guard let family = assessment.family?.family else { return nil }

        let genus = assessment.genus
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0.capitalized }

        var epithet = assessment.specificEpithet
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : $0 }

        // An epithet without a genus is half a name. `Taxon` drops it anyway;
        // doing it here keeps the confidence honest about what was kept.
        if genus == nil { epithet = nil }

        var taxon = Taxon(family: family, genus: genus, specificEpithet: epithet)

        // If the catalogue knows this genus, it also knows which family it
        // belongs to, and the catalogue is right. A model that says
        // "Boraginaceae, Trifolium" has contradicted itself, and the genus is
        // the more specific claim, so the family is corrected rather than the
        // answer thrown away.
        if let genus,
           let known = FlowerCatalogue.all.first(where: { $0.taxon.genus == genus }),
           known.family != family {
            logger.info("model gave \(genus) in the wrong family; using the catalogue's")
            taxon = Taxon(
                family: known.family,
                genus: genus,
                specificEpithet: epithet
            )
        }

        let confidence = assessment.confidence.isFinite
            ? min(1, max(0, assessment.confidence))
            : 0

        return (taxon, confidence)
    }

    /// Written to push against the model's instinct to give a definite answer.
    ///
    /// A general model would rather name a species than admit to a family, and
    /// that instinct is exactly wrong here: a wrong species gives the patch
    /// the wrong corolla depth and the wrong bloom season, where a correct
    /// family gives it very nearly the right ones.
    private var instructions: String {
        """
        You identify plants from photographs for a beekeeping simulation.

        Answer at the finest rank you are genuinely sure of and stop there. A \
        correct family is worth far more than a guessed species: the \
        simulation uses the family to work out whether a honey bee can reach \
        the nectar, so a wrong species produces a plainly false result while \
        an honest family produces a nearly right one.

        Leave the genus and species fields empty unless the photograph makes \
        them unmistakable. Most photographs of wild flowers cannot be placed \
        to a species and should not be.

        Report the family only from the list you are given. If the plant does \
        not belong to any of them, leave the family empty.
        """
    }
}
