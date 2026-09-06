import XCTest
@testable import FlowerPowerCore

/// Naming a flower by nearest neighbour.
///
/// Tested with synthetic vectors rather than real feature prints, because the
/// part that can be wrong is the arithmetic and the thresholds — producing the
/// vectors is Vision's job and needs an Apple platform. What matters here is
/// that a photograph of something the library has never seen comes back
/// unnamed rather than confidently mislabelled: a patch identified as the
/// wrong species gets the wrong nectar richness and the wrong bloom season,
/// and tells the player something false about the world.
final class FeaturePrintLibraryTests: XCTestCase {

    /// A point in a small space, so distances are easy to reason about.
    private func print(_ values: Float...) -> FeaturePrint {
        FeaturePrint(values)
    }

    private func library(
        maximumDistance: Float = 1.1,
        neighbours: Int = 5
    ) -> FeaturePrintLibrary {
        var library = FeaturePrintLibrary(references: [
            SpeciesReference(speciesID: "white_clover", print: print(0, 0, 0)),
            SpeciesReference(speciesID: "white_clover", print: print(0.1, 0, 0)),
            SpeciesReference(speciesID: "white_clover", print: print(0, 0.1, 0)),
            SpeciesReference(speciesID: "heather", print: print(5, 0, 0)),
            SpeciesReference(speciesID: "heather", print: print(5.1, 0, 0)),
            SpeciesReference(speciesID: "heather", print: print(5, 0.1, 0))
        ])
        library.maximumDistance = maximumDistance
        library.neighbours = neighbours
        return library
    }

    // MARK: - Distance

    func testDistanceIsStraightLine() throws {
        let threeFourFive = try XCTUnwrap(print(0, 0, 0).distance(to: print(3, 4, 0)))
        XCTAssertEqual(threeFourFive, 5, accuracy: 0.0001)

        XCTAssertEqual(try XCTUnwrap(print(1, 2, 3).distance(to: print(1, 2, 3))), 0)
    }

    /// Feature print length depends on which Vision revision produced it.
    /// Comparing across lengths by truncating would give a number that looks
    /// like a distance and means nothing at all.
    func testPrintsOfDifferentLengthsCannotBeCompared() {
        XCTAssertNil(print(1, 2).distance(to: print(1, 2, 3)))
        XCTAssertNil(print().distance(to: print(1)))
    }

    // MARK: - Identifying

    func testAPhotographNearAReferenceIsNamed() throws {
        let matches = library().matches(for: print(0.05, 0.05, 0))
        let best = try XCTUnwrap(matches.first)

        XCTAssertEqual(best.speciesID, "white_clover")
        XCTAssertGreaterThan(best.confidence, 0.5)
    }

    /// The one that matters. Something the library has never seen must come
    /// back with nothing, not with whichever reference happened to be least
    /// far away.
    func testAPhotographOfSomethingElseIsNotNamed() {
        XCTAssertTrue(
            library().matches(for: print(50, 50, 50)).isEmpty,
            "a flower nothing in the library resembles should be unidentified, "
            + "not identified as the nearest thing in the box"
        )
    }

    func testAnEmptyLibraryNamesNothing() {
        XCTAssertTrue(FeaturePrintLibrary().matches(for: print(0, 0, 0)).isEmpty)
    }

    func testAnEmptyPrintNamesNothing() {
        XCTAssertTrue(library().matches(for: FeaturePrint([])).isEmpty)
    }

    /// Confidence has to fall off with distance, because it scales the yield
    /// the player gets. A far-but-still-inside-the-threshold match should be
    /// worth visibly less than one sitting on top of a reference.
    func testConfidenceFallsOffWithDistance() throws {
        let near = try XCTUnwrap(library().matches(for: print(0.02, 0, 0)).first)
        let far = try XCTUnwrap(library().matches(for: print(0.9, 0, 0)).first)

        XCTAssertEqual(near.speciesID, "white_clover")
        XCTAssertEqual(far.speciesID, "white_clover")
        XCTAssertGreaterThan(near.confidence, far.confidence)
        XCTAssertLessThan(far.confidence, 0.4)
    }

    /// A photograph sitting between two species should be reported as
    /// uncertain rather than as a confident call on whichever won by a hair.
    func testAnAmbiguousPhotographIsReportedAsUncertain() throws {
        var ambiguous = FeaturePrintLibrary(references: [
            SpeciesReference(speciesID: "white_clover", print: print(0, 0, 0)),
            SpeciesReference(speciesID: "heather", print: print(1, 0, 0))
        ])
        ambiguous.maximumDistance = 2
        ambiguous.neighbours = 2

        let matches = ambiguous.matches(for: print(0.5, 0, 0))

        XCTAssertEqual(matches.count, 2, "both should be offered")
        XCTAssertLessThan(
            try XCTUnwrap(matches.first).confidence, 0.6,
            "neither is a confident answer"
        )
    }

    func testRunnersUpAreOffered() {
        var wide = library(maximumDistance: 20)
        wide.neighbours = 6

        let matches = wide.matches(for: print(0.05, 0, 0))
        XCTAssertEqual(matches.first?.speciesID, "white_clover")
        XCTAssertTrue(
            matches.contains { $0.speciesID == "heather" },
            "the alternatives are what the did-you-mean buttons are built from"
        )
    }

    func testMatchesResolveToRealSpecies() throws {
        let identified = library().identifications(for: print(0.05, 0, 0))
        let best = try XCTUnwrap(identified.first)

        XCTAssertEqual(best.species.commonName, "White Clover")
        XCTAssertGreaterThan(best.confidence, 0)
    }

    /// A reference for a species the catalogue no longer has must not crash or
    /// surface — the library outlives any one version of the catalogue.
    func testReferencesForUnknownSpeciesAreDropped() {
        var stale = FeaturePrintLibrary(references: [
            SpeciesReference(speciesID: "triffid", print: print(0, 0, 0))
        ])
        stale.maximumDistance = 2

        XCTAssertFalse(stale.matches(for: print(0, 0, 0)).isEmpty)
        XCTAssertTrue(stale.identifications(for: print(0, 0, 0)).isEmpty)
    }

    // MARK: - Growing

    func testNamingAFlowerAddsAReference() {
        var growing = FeaturePrintLibrary()
        growing.add(SpeciesReference(
            speciesID: "borage", print: print(1, 1, 1), source: .named
        ))

        XCTAssertEqual(growing.speciesCovered, ["borage"])
    }

    func testEmptyPrintsAreNotKept() {
        var growing = FeaturePrintLibrary()
        growing.add(SpeciesReference(speciesID: "borage", print: FeaturePrint([])))

        XCTAssertTrue(growing.isEmpty)
    }

    /// Without a cap, a player who photographs a great deal of clover ends up
    /// with a library that is mostly clover — which biases every lookup toward
    /// whatever they photograph most.
    func testASpeciesCannotFloodTheLibrary() {
        var growing = FeaturePrintLibrary()
        growing.referencesPerSpecies = 4

        for index in 0..<20 {
            growing.add(SpeciesReference(
                speciesID: "white_clover",
                print: print(Float(index), 0, 0),
                source: .named
            ))
        }

        XCTAssertEqual(growing.references.count, 4)
    }

    /// The curated references are the ones that were checked, so they should
    /// outlast anything picked up during play.
    func testBundledReferencesAreKeptOverLearnedOnes() {
        var growing = FeaturePrintLibrary()
        growing.referencesPerSpecies = 3
        growing.add(SpeciesReference(
            speciesID: "ivy", print: print(0, 0, 0), source: .bundled
        ))

        for index in 1..<10 {
            growing.add(SpeciesReference(
                speciesID: "ivy", print: print(Float(index), 0, 0), source: .named
            ))
        }

        XCTAssertEqual(growing.references.count, 3)
        XCTAssertTrue(
            growing.references.contains { $0.source == .bundled },
            "the reference that was curated should not be evicted by play"
        )
    }

    func testTheLibraryRoundTrips() throws {
        let original = library()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FeaturePrintLibrary.self, from: data)

        XCTAssertEqual(restored.references, original.references)
        XCTAssertEqual(
            restored.matches(for: print(0.05, 0, 0)).first?.speciesID,
            "white_clover"
        )
    }
}
