import Testing
@testable import FlowerPowerCore

/// What the UX walkthrough of 2026-11-07 found in the engine's half of the
/// interface. See UX-WALKTHROUGH-2026-11-07.md at the repository root.
@Suite("UX walkthrough, 2026-11-07")
struct WalkthroughRegressionTests {

    /// Finding 3. In winter the headline said "short of stores" while the
    /// status, which only looked at stores in autumn, said "Steady".
    @Test("A colony short of winter stores is not called steady in winter")
    func winterShortfallIsStruggling() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 7_107)
        simulation.mutateWorld { world in
            let need = world.hive.winterStoresRequired
            world.hive.resources = ResourcePool()
            // Well clear of the laying floor, so the verdict is about the
            // winter rather than about starving today.
            world.hive.resources.add(max(need * 0.3, 20), of: .honey)
        }
        let hive = simulation.world.hive
        #expect(hive.isShortForWinter)
        #expect(ColonyStatus.evaluate(hive: hive, season: .winter, config: .standard) == .struggling)
    }

    @Test("A colony with its winter stores is not marked short")
    func winterReadyIsNotShort() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 7_108)
        simulation.mutateWorld { world in
            world.hive.resources.add(world.hive.winterStoresRequired * 2, of: .honey)
        }
        #expect(!simulation.world.hive.isShortForWinter)
    }

    /// Finding 6. The report kept no record of a disease going away, so its
    /// health card said only that it had appeared.
    @Test("The report records a cleared infection, and keeps it across a merge")
    func clearedInfectionsAreRecorded() {
        var first = CatchUpReport()
        first.record(.infectionDetected(.americanFoulbrood))
        first.record(.infectionCleared(.americanFoulbrood))
        #expect(first.clearedInfections == [.americanFoulbrood])

        var later = CatchUpReport()
        later.record(.infectionCleared(.varroa))
        #expect(first.merging(later).clearedInfections == [.americanFoulbrood, .varroa])
    }

    /// Finding 5. "The colony cleared american foulbrood."
    @Test("A disease named mid-sentence keeps its proper noun")
    func diseaseNameInSentence() {
        #expect(SimEvent.infectionCleared(.americanFoulbrood).narration
                == "The colony cleared American foulbrood.")
        #expect(SimEvent.infectionCleared(.varroa).narration == "The colony cleared varroa mites.")
    }

    /// Finding 4. The cave was "safe" and "cold" beside bars that drew it as
    /// the warmest site and a middling one to defend.
    @Test("The cave's description agrees with its numbers")
    func caveCopyMatchesNumbers() {
        let cave = HiveLocationType.cave
        #expect(cave.insulation >= HiveLocationType.livingTreeCavity.insulation)
        #expect(!cave.summary.localizedCaseInsensitiveContains("cold"))
        #expect(!cave.summary.localizedCaseInsensitiveContains("safe"))
    }
}
