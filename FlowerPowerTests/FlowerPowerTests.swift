//
//  FlowerPowerTests.swift
//  FlowerPowerTests
//
//  The app target's own tests. Almost everything worth testing lives in the
//  package instead — that is deliberate, because the package builds and runs
//  without a Mac — so what is left here is the handful of invariants that can
//  only be checked where the Apple frameworks are.
//
//  These have never been run. They need Xcode.
//

import Testing
import FoundationModels
import FlowerPowerCore
@testable import FlowerPower

@Suite("On-device placement")
struct TaxonomicClassifierTests {

    /// The on-device model picks a family from a closed list, and that list is
    /// a hand-written mirror of `PlantFamily` — the engine also builds on
    /// Windows and cannot import FoundationModels, so the vocabulary exists
    /// twice.
    ///
    /// Drift is the obvious failure and a quiet one: a family added to the
    /// engine but not the mirror simply never gets chosen, and a family in the
    /// mirror the engine does not have comes back as an unplaceable answer.
    @Test("Every family the game models can be chosen by the model")
    func familyListsAgree() {
        let engine = Set(PlantFamily.allCases.map(\.rawValue))
        let generable = Set(GenerableFamily.allCases.map(\.rawValue))

        #expect(engine == generable, """
            the model's family list has drifted from the engine's. \
            Only in the engine: \(engine.subtracting(generable).sorted()). \
            Only in the model's list: \(generable.subtracting(engine).sorted()).
            """)
    }

    @Test("Every choice maps to a real family", arguments: GenerableFamily.allCases)
    func everyChoiceResolves(choice: GenerableFamily) {
        #expect(choice.family != nil)
    }

    // MARK: - Reading an answer

    private func assessment(
        plant: Bool = true,
        family: GenerableFamily? = .fabaceae,
        genus: String? = nil,
        epithet: String? = nil,
        confidence: Double = 0.8
    ) -> FlowerAssessment {
        FlowerAssessment(
            isFloweringPlant: plant,
            family: family,
            genus: genus,
            specificEpithet: epithet,
            confidence: confidence
        )
    }

    @Test("A photograph that is not a plant is refused")
    func notAPlant() {
        let classifier = TaxonomicClassifier()
        #expect(classifier.taxon(from: assessment(plant: false)) == nil)
    }

    @Test("An answer with no family is refused")
    func noFamily() {
        let classifier = TaxonomicClassifier()
        #expect(classifier.taxon(from: assessment(family: nil)) == nil)
    }

    @Test("A family alone is a real answer")
    func familyOnly() throws {
        let classifier = TaxonomicClassifier()
        let placed = try #require(classifier.taxon(from: assessment()))

        #expect(placed.taxon.rank == .family)
        #expect(placed.taxon.family == .fabaceae)
    }

    @Test("Names are normalised to botanical convention")
    func normalisation() throws {
        let classifier = TaxonomicClassifier()
        let placed = try #require(classifier.taxon(from: assessment(
            genus: "  trifolium ", epithet: " REPENS "
        )))

        #expect(placed.taxon.genus == "Trifolium")
        #expect(placed.taxon.specificEpithet == "repens")
        #expect(placed.taxon.scientificName == "Trifolium repens")
    }

    /// An epithet with no genus is half a name, and would make the placement
    /// claim a precision it does not have.
    @Test("An epithet without a genus is dropped")
    func epithetWithoutGenus() throws {
        let classifier = TaxonomicClassifier()
        let placed = try #require(classifier.taxon(from: assessment(epithet: "repens")))

        #expect(placed.taxon.rank == .family)
    }

    /// A model can contradict itself. The genus is the more specific claim and
    /// the catalogue knows which family it belongs to, so the family is
    /// corrected rather than the whole answer thrown away.
    @Test("A genus in the wrong family corrects the family")
    func contradictoryFamily() throws {
        let classifier = TaxonomicClassifier()
        let placed = try #require(classifier.taxon(from: assessment(
            family: .boraginaceae, genus: "Trifolium", epithet: "repens"
        )))

        #expect(placed.taxon.family == .fabaceae)
        #expect(placed.taxon.genus == "Trifolium")
    }

    @Test("Confidence is clamped", arguments: [
        (Double.nan, 0.0), (.infinity, 0.0), (5, 1), (-2, 0), (0.4, 0.4)
    ])
    func confidenceClamping(given: Double, expected: Double) throws {
        let classifier = TaxonomicClassifier()
        let placed = try #require(classifier.taxon(from: assessment(confidence: given)))

        #expect(placed.confidence == expected)
    }

    // MARK: - Availability

    /// Availability has to be readable rather than a bare boolean, because
    /// "your device cannot" and "turn Apple Intelligence on" want different
    /// things said to the player.
    @Test("Unavailability has a reason a person can act on")
    func availabilityIsExplained() {
        if case .failure(let reason) = TaxonomicClassifier.availability {
            #expect(reason.errorDescription?.isEmpty == false)
        }
    }
}
