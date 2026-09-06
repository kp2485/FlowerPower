import Testing
import Foundation
@testable import FlowerPowerCore

/// Winter: a quarter of the year with nothing to photograph.
///
/// The pacing note in `SimClock` argues the answer is something to *do* in
/// winter rather than a faster clock. This is the reading half of that — the
/// colony's own account of the year it has just finished — plus the honest
/// framing of the season itself, which had been a single sentence repeated for
/// ninety simulated days.
@Suite("Winter")
struct WinterTests {

    // MARK: - The season reads differently as it goes

    /// "Clustered for winter." for ninety days was the whole of it. At double
    /// speed that is still the best part of a real week, during which the one
    /// line the game offers a player who opens it never changed.
    @Test("The winter headline changes as the winter goes on")
    func winterHeadlineMoves() {
        var seen: Set<String> = []
        for dayOfWinter in stride(from: 0, to: Season.daysPerSeason, by: 6) {
            var simulation = Fixture.thrivingSimulation(config: .standard, seed: 5_050)
            simulation.mutateWorld { world in
                // Comfortably provisioned, so this is about the season rather
                // than about being short.
                world.hive.resources.add(2_000, of: .honey)
            }
            simulation.setDay(Season.daysPerSeason * 3 + dayOfWinter)
            seen.insert(simulation.snapshot().headline)
        }

        #expect(seen.count >= 3, "winter still reads as one sentence: \(seen)")
        for line in seen {
            #expect(!line.isEmpty)
            #expect(line.hasSuffix("."))
        }
    }

    /// Being short of stores is the one thing worth saying instead.
    @Test("A colony short of stores is told so, with the days left")
    func shortHeadlineWins() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 5_051)
        simulation.setDay(Season.daysPerSeason * 3 + 20)
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool()
            world.hive.resources.add(5, of: .honey)
        }

        let snapshot = simulation.snapshot()
        #expect(snapshot.headline.contains("short of stores"))
        #expect(snapshot.headline.contains("\(snapshot.daysUntilSpring)"))
    }

    @Test("The days to spring count down")
    func daysUntilSpring() {
        var early = Fixture.thrivingSimulation(config: .standard, seed: 5_052)
        early.setDay(Season.daysPerSeason * 3 + 10)
        var late = Fixture.thrivingSimulation(config: .standard, seed: 5_052)
        late.setDay(Season.daysPerSeason * 3 + 80)

        #expect(early.snapshot().daysUntilSpring > late.snapshot().daysUntilSpring)
        #expect(
            late.snapshot().daysUntilSpring
                == Season.daysPerYear - (Season.daysPerSeason * 3 + 80)
        )
    }

    // MARK: - The year, read back

    @Test("A year that had nothing in it says so rather than padding")
    func quietYear() {
        let almanac = Almanac()
        let review = almanac.review(year: 1, lineage: Lineage())

        #expect(review.isEmpty)
        #expect(review.notes.isEmpty, "a quiet year should not be padded out")
        #expect(review.headline.contains("first year"))
    }

    /// Counted from the events as the lines are written, rather than read back
    /// out of the prose: "swarm cells are started", "a swarm leaves" and "the
    /// swarm is called off" are all `.swarm` entries and mean different things.
    @Test("The year's numbers come from the events, not from the prose")
    func tallyIsTyped() {
        var almanac = Almanac()
        let lineage = Lineage()

        almanac.chronicle(
            [.queenCellStarted(.swarm), .swarmAbandoned],
            day: 100, honey: 40, lineage: lineage
        )
        // Two `.swarm` lines were written, and no swarm happened.
        let swarmLines = almanac.entries(inYear: 1).filter { $0.kind == .swarm }.count
        #expect(swarmLines == 2)
        #expect(almanac.review(year: 1, lineage: lineage).tally.swarms == 0)

        almanac.chronicle([.swarmed(beesLost: 240)], day: 110, honey: 40, lineage: lineage)
        #expect(almanac.review(year: 1, lineage: lineage).tally.swarms == 1)
    }

    @Test("A year with things in it reads as an account of them")
    func eventfulYear() {
        var almanac = Almanac()
        let lineage = Lineage()

        almanac.chronicle([.swarmed(beesLost: 240)], day: 120, honey: 300, lineage: lineage)
        almanac.chronicle([.queenEmerged(quality: 0.9)], day: 126, honey: 280, lineage: lineage)
        almanac.chronicle([.queenMated(patrilines: 14)], day: 134, honey: 275, lineage: lineage)
        almanac.chronicle([.attacked(.wasp)], day: 200, honey: 400, lineage: lineage)
        almanac.chronicle([.attackRepelled(.wasp)], day: 200, honey: 400, lineage: lineage)
        almanac.chronicle([.attacked(.badger)], day: 210, honey: 380, lineage: lineage)
        almanac.chronicle([.honeyTaken(30)], day: 250, honey: 350, lineage: lineage)

        let review = almanac.review(year: 1, lineage: lineage)

        #expect(review.tally.swarms == 1)
        #expect(review.tally.queensRaised == 1)
        #expect(review.tally.queensMated == 1)
        #expect(review.tally.raids == 2)
        #expect(review.tally.raidsRepelled == 1)
        #expect(review.tally.honeyTaken == 30)
        #expect(review.tally.peakHoney == 400)

        // Bound rather than written inline: `contains(where:)` is `rethrows`,
        // and `#expect` will not expand a trailing closure on one.
        let saysThePeak = review.notes.contains { $0.contains("400") }
        let saysWhatWasTaken = review.notes.contains { $0.contains("30") }
        let saysTheRaids = review.notes.contains {
            $0.contains("2 raids") && $0.contains("1 driven off")
        }
        let saysSheMated = review.notes.contains { $0.contains("every one of them mated") }

        #expect(review.headline.contains("swarm"))
        #expect(saysThePeak, "the peak is worth saying")
        #expect(saysWhatWasTaken, "what the player took is worth saying")
        #expect(saysTheRaids)
        #expect(saysSheMated)
    }

    /// The gap between queens raised and queens mated is the year's real risk,
    /// and a player who never watches a mating flight would otherwise never
    /// see it.
    @Test("A queen who did not come back is counted as not coming back")
    func matingLossIsNamed() {
        var almanac = Almanac()
        let lineage = Lineage()
        almanac.chronicle([.queenEmerged(quality: 0.9)], day: 100, honey: 100, lineage: lineage)
        almanac.chronicle([.queenEmerged(quality: 0.9)], day: 130, honey: 100, lineage: lineage)
        almanac.chronicle([.queenMated(patrilines: 12)], day: 140, honey: 100, lineage: lineage)

        let review = almanac.review(year: 1, lineage: lineage)
        let saysSheDidNotReturn = review.notes.contains { $0.contains("never came back") }
        #expect(saysSheDidNotReturn)
    }

    @Test("Years are kept apart, and in order")
    func yearsAreSeparate() {
        var almanac = Almanac()
        let lineage = Lineage()
        // Written out of order on purpose.
        almanac.chronicle(
            [.swarmed(beesLost: 100)], day: Season.daysPerYear + 40, honey: 10, lineage: lineage
        )
        almanac.chronicle([.swarmed(beesLost: 200)], day: 40, honey: 10, lineage: lineage)

        #expect(almanac.years == [1, 2], "years came back out of order")
        #expect(almanac.review(year: 1, lineage: lineage).tally.swarms == 1)
        #expect(almanac.review(year: 2, lineage: lineage).tally.swarms == 1)
        #expect(almanac.review(year: 2, lineage: lineage).headline.contains("second"))
    }

    /// Saves written before the tallies existed have to keep opening.
    @Test("An almanac from an older save still decodes")
    func oldSaveDecodes() throws {
        let json = #"{"entries":[],"peakHoney":123.0}"#
        let almanac = try JSONDecoder().decode(Almanac.self, from: Data(json.utf8))

        #expect(almanac.peakHoney == 123)
        #expect(almanac.tallies.isEmpty)
        #expect(almanac.review(year: 1, lineage: Lineage()).isEmpty)
    }

    @Test("An almanac round-trips with its tallies")
    func roundTrip() throws {
        var almanac = Almanac()
        almanac.chronicle([.swarmed(beesLost: 12)], day: 30, honey: 55, lineage: Lineage())

        let restored = try JSONDecoder().decode(
            Almanac.self, from: JSONEncoder().encode(almanac)
        )
        #expect(restored == almanac)
        #expect(restored.tally(forYear: 1)?.swarms == 1)
    }

    /// The snapshot carries both halves the review needs, so a view should not
    /// have to know that it takes two of them.
    @Test("The snapshot can hand the interface a year to read")
    func snapshotReads() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 5_053)
        #expect(simulation.snapshot().year == 1)
        #expect(simulation.snapshot().hasSomethingToRead == false)

        simulation.mutateWorld { world in
            world.almanac.chronicle(
                [.swarmed(beesLost: 50)], day: 100, honey: 200, lineage: world.lineage
            )
        }

        let snapshot = simulation.snapshot()
        #expect(snapshot.hasSomethingToRead)
        #expect(snapshot.review(year: snapshot.yearWorthReading).tally.swarms == 1)
    }

    // MARK: - There is still something to look for

    /// Two keystone plants flower in winter, and they are the only things that
    /// do. Hiding the bloom prompt in winter — which the dashboard did — takes
    /// away the one season where knowing that matters most.
    @Test("Winter has flowers, and they are the ones that matter")
    func winterHasKeystones() {
        let flowering = FlowerCatalogue.inBloom(during: .winter)
        let allKeystones = flowering.allSatisfy(\.isKeystone)

        #expect(!flowering.isEmpty, "nothing flowers in winter, so there is nothing to prompt")
        #expect(
            allKeystones,
            "everything that flowers in winter should be a keystone; that is what winter means"
        )
    }
}
