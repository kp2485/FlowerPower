import XCTest
@testable import FlowerPowerCore

/// Turning a trained model's class names into species the game knows.
///
/// This is the seam where an external vocabulary meets ours, and it is
/// entirely untestable on device — by the time a wrong answer shows up there,
/// it looks like a bad model rather than a bad lookup.
final class ClassifierLabelTests: XCTestCase {

    // MARK: - The obvious cases

    func testOurOwnIdentifiersMatch() {
        XCTAssertEqual(FlowerCatalogue.match(label: "white_clover")?.id, "white_clover")
        XCTAssertEqual(FlowerCatalogue.match(label: "white clover")?.id, "white_clover")
        XCTAssertEqual(FlowerCatalogue.match(label: "WHITE_CLOVER")?.id, "white_clover")
    }

    func testCommonAndScientificNamesMatch() {
        XCTAssertEqual(FlowerCatalogue.match(label: "Pussy Willow")?.id, "willow")
        XCTAssertEqual(FlowerCatalogue.match(label: "Salix caprea")?.id, "willow")
        XCTAssertEqual(FlowerCatalogue.match(label: "Calluna vulgaris")?.id, "heather")
    }

    /// The whole reason the alias table exists: three datasets, three names,
    /// one flower.
    func testSynonymsFromDifferentVocabulariesAgree() {
        for label in ["corn poppy", "Papaver rhoeas", "common poppy", "field poppy"] {
            XCTAssertEqual(
                FlowerCatalogue.match(label: label)?.id, "poppy",
                "\(label) should be the poppy"
            )
        }

        for label in ["rapeseed", "canola", "Brassica napus", "oilseed rape"] {
            XCTAssertEqual(FlowerCatalogue.match(label: label)?.id, "oilseed_rape", label)
        }
    }

    func testPunctuationAndSeparatorsDoNotMatter() {
        XCTAssertEqual(FlowerCatalogue.match(label: "viper's bugloss")?.id, "vipers_bugloss")
        XCTAssertEqual(FlowerCatalogue.match(label: "vipers bugloss")?.id, "vipers_bugloss")
        XCTAssertEqual(FlowerCatalogue.match(label: "oregon-grape")?.id, "mahonia")
        XCTAssertEqual(FlowerCatalogue.match(label: "  Ice  Plant  ")?.id, "sedum")
    }

    // MARK: - The trap

    /// The original matcher fell back to a plain substring test in both
    /// directions. With `Ivy` in the catalogue, every one of these resolved to
    /// Hedera helix — a keystone autumn forage plant — and none of them is it.
    func testShortNamesDoNotSwallowUnrelatedLabels() {
        for label in ["poison ivy", "Boston ivy", "ivy-leaved toadflax", "ivy gourd"] {
            XCTAssertNil(
                FlowerCatalogue.match(label: label),
                "\(label) is not Hedera helix and must not be identified as it"
            )
        }
    }

    /// A name that merely sounds like one of ours is not one of ours.
    func testSimilarSoundingPlantsAreNotMatched() {
        XCTAssertNil(FlowerCatalogue.match(label: "canterbury bells"),
                     "Campanula is not Hyacinthoides")
        XCTAssertNil(FlowerCatalogue.match(label: "blackberry lily"),
                     "Iris domestica is not a bramble")
        XCTAssertNil(FlowerCatalogue.match(label: "mexican petunia"))
        XCTAssertNil(FlowerCatalogue.match(label: "desert rose"))
    }

    func testNonsenseMatchesNothing() {
        XCTAssertNil(FlowerCatalogue.match(label: ""))
        XCTAssertNil(FlowerCatalogue.match(label: "   "))
        XCTAssertNil(FlowerCatalogue.match(label: "car door"))
        XCTAssertNil(FlowerCatalogue.match(label: "n02123045"))
    }

    // MARK: - Longer labels

    /// Some datasets label with more than a name.
    func testANameInsideALongerLabelIsFound() {
        XCTAssertEqual(
            FlowerCatalogue.match(label: "purple coneflower (Echinacea purpurea)")?.id,
            "echinacea"
        )
        XCTAssertEqual(
            FlowerCatalogue.match(label: "Asteraceae common dandelion")?.id,
            "dandelion"
        )
    }

    /// The more specific reading wins. Both heathers are in the catalogue and
    /// they bloom in different seasons, so confusing them is not cosmetic.
    func testTheMoreSpecificNameWins() {
        XCTAssertEqual(FlowerCatalogue.match(label: "winter heath")?.id, "winter_heather")
        XCTAssertEqual(FlowerCatalogue.match(label: "Erica carnea")?.id, "winter_heather")
        XCTAssertEqual(FlowerCatalogue.match(label: "common heather")?.id, "heather")
    }

    // MARK: - The table itself

    func testEveryAliasPointsAtARealSpecies() {
        for (id, names) in ClassifierLabels.aliases {
            XCTAssertNotNil(
                FlowerCatalogue.species(withID: id),
                "alias table names '\(id)', which is not in the catalogue"
            )
            XCTAssertFalse(names.isEmpty, "\(id) has no aliases")
        }
    }

    func testEverySpeciesHasAliases() {
        for species in FlowerCatalogue.all {
            XCTAssertNotNil(
                ClassifierLabels.aliases[species.id],
                "\(species.id) has no aliases, so a model can only ever name it "
                + "by our own identifier"
            )
        }
    }

    /// Two species claiming the same alias would make identification depend on
    /// dictionary ordering, which is not stable. A species listing the same
    /// alias twice is only untidy, but it is worth knowing about — hyphens and
    /// underscores are flattened, so two spellings can collide without looking
    /// alike.
    func testNoAliasIsClaimedTwice() {
        var seen: [String: String] = [:]
        for (id, names) in ClassifierLabels.aliases {
            for name in names {
                let key = ClassifierLabels.normalise(name)
                guard let existing = seen[key] else {
                    seen[key] = id
                    continue
                }
                if existing == id {
                    XCTFail("\(id) lists '\(key)' more than once")
                } else {
                    XCTFail("'\(key)' is claimed by both \(existing) and \(id)")
                }
            }
        }
    }

    /// Round trip: every alias resolves to the species that declared it.
    func testEveryAliasResolvesBackToItsOwnSpecies() {
        for (id, names) in ClassifierLabels.aliases {
            for name in names {
                XCTAssertEqual(
                    FlowerCatalogue.match(label: name)?.id, id,
                    "'\(name)' should resolve to \(id)"
                )
            }
        }
    }
}
