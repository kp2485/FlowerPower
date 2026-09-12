import Testing
import Foundation
@testable import FlowerPowerCore

/// Feeding the colony: the harvest run backwards.
///
/// `takeHoney` was a dead end — the honey went into `world.honeyTaken`, which
/// was the score and nothing else. Real beekeepers feed a colony that is
/// short, and a player who took a crop in a good autumn should be able to
/// answer for it in a bad winter.
///
/// The rules these tests hold to the same line as every other decision:
/// instinct is the default, so a colony nobody feeds does exactly what it did
/// before feeding existed; the amount is capped by what is really possible
/// rather than by what the player asked for; and fed honey is honey, stored in
/// the same pool the bees eat from.
@Suite("Feeding")
struct FeedingTests {

    /// A colony with drawn comb, a bank, and stores it can be moved around.
    private func banked(
        honey: Double,
        bank: Double,
        seed: UInt64 = 4_100
    ) -> Simulation {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: seed)
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool()
            world.hive.resources.add(honey, of: .honey)
            world.honeyTaken = bank
        }
        return simulation
    }

    // MARK: - What goes in

    @Test("Feeding moves honey out of the bank and into the stores")
    func feedingMovesHoney() {
        var simulation = banked(honey: 50, bank: 100)

        let given = simulation.feed(40)

        #expect(abs(given - 40) < 0.001)
        #expect(abs(simulation.hive.resources[.honey] - 90) < 0.001)
        #expect(abs(simulation.world.honeyTaken - 60) < 0.001)
    }

    @Test("Feeding is capped by what the player actually banked")
    func cappedByTheBank() {
        var simulation = banked(honey: 10, bank: 25)

        let given = simulation.feed(10_000)

        #expect(abs(given - 25) < 0.001)
        #expect(abs(simulation.world.honeyTaken) < 0.001)
        #expect(abs(simulation.hive.resources[.honey] - 35) < 0.001)
        #expect(!simulation.canFeed, "the bank is empty")
    }

    /// The same clamp `ForagingSystem` puts on nectar coming in: what the
    /// colony can take is what its free cells will hold. A hive with nowhere
    /// to put honey cannot be given any.
    @Test("Feeding is capped by the comb there is to store it in")
    func cappedByTheComb() {
        var simulation = banked(honey: 0, bank: 500)
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 20, droneCells: 0, capacity: 400)
            world.hive.bees.removeAll { !$0.isAdult }
        }

        let space = Double(simulation.hive.freeCells) * ResourceKind.honey.unitsPerCell
        #expect(space > 0)
        #expect(abs(simulation.feedOnOffer - space) < 0.001)

        let given = simulation.feed(500)
        #expect(abs(given - space) < 0.001)
        #expect(simulation.hive.freeCells == 0)
        #expect(!simulation.canFeed, "no room, whatever is in the bank")
    }

    @Test("A colony with nothing banked cannot be fed")
    func nothingBanked() {
        var simulation = banked(honey: 30, bank: 0)

        #expect(!simulation.canFeed)
        #expect(abs(simulation.feedOnOffer) < 0.001)
        #expect(simulation.feed(50) == 0)
        #expect(abs(simulation.hive.resources[.honey] - 30) < 0.001)
    }

    @Test("Feeding nothing, or less than nothing, does nothing")
    func feedingNothing() {
        var simulation = banked(honey: 30, bank: 100)
        #expect(simulation.feed(0) == 0)
        #expect(simulation.feed(-40) == 0)
        #expect(abs(simulation.world.honeyTaken - 100) < 0.001)
    }

    // MARK: - The shortfall, and the window

    @Test("The shortfall is the number the stores summary reports")
    func shortfallMatchesTheSummary() {
        let simulation = banked(honey: 40, bank: 100)
        let stores = simulation.snapshot().stores

        #expect(
            abs(simulation.storesShortfall
                - (stores.winterRequirement - stores.edibleEnergy)) < 0.001
        )
        #expect(abs(simulation.snapshot().storesShortfall - simulation.storesShortfall) < 0.001)
        #expect(abs(simulation.snapshot().feedOnOffer - simulation.feedOnOffer) < 0.001)
    }

    @Test("A colony with enough put by is not short")
    func noShortfallWhenProvisioned() {
        var simulation = banked(honey: 0, bank: 100)
        simulation.mutateWorld { world in
            world.hive.resources.add(world.hive.winterStoresRequired * 1.2, of: .honey)
        }
        #expect(simulation.storesShortfall == 0)
        #expect(!simulation.feedDecisionOpen, "nothing to answer")
    }

    /// The cue is the winter-shortage alert and nothing else: short of stores,
    /// in the seasons where that is the question, with honey banked to give.
    @Test("The decision opens when the colony is short and there is honey banked")
    func windowOpens() {
        var short = banked(honey: 20, bank: 200)
        short.setDay(Season.daysPerSeason * 2 + 40)
        #expect(short.feedDecisionOpen)
        #expect(short.snapshot().feedDecisionOpen)

        var noBank = banked(honey: 20, bank: 0)
        noBank.setDay(Season.daysPerSeason * 2 + 40)
        #expect(!noBank.feedDecisionOpen, "nothing to give")

        var winter = banked(honey: 20, bank: 200)
        winter.setDay(Season.daysPerSeason * 3 + 30)
        #expect(winter.feedDecisionOpen, "the winter is what a bank is for")

        var spring = banked(honey: 20, bank: 200)
        spring.setDay(10)
        #expect(
            !spring.feedDecisionOpen,
            "a spring colony is short of a winter it has just survived"
        )
    }

    @Test("The winter-stores alert points at the bank when there is one")
    func alertMentionsTheBank() {
        var simulation = banked(honey: 20, bank: 200)
        simulation.setDay(Season.daysPerSeason * 2 + 40)

        let alert = simulation.snapshot().alerts.first { $0.kind == .winterStoresLow }
        #expect(alert != nil)
        #expect(alert?.suggestion?.contains("200") == true)
    }

    // MARK: - The record

    @Test("The event says how much went back")
    func theEventNarrates() {
        #expect(SimEvent.fed(18).narration.contains("18"))
        #expect(SimEvent.fed(18).isHighlight)
        #expect(SimEvent.fed(18).narration != SimEvent.honeyTaken(18).narration)
    }

    @Test("Feeding is written into the almanac")
    func theAlmanacRecordsIt() {
        var simulation = banked(honey: 20, bank: 200)
        simulation.feed(60)

        let lines = simulation.world.almanac.entries.filter { $0.kind == .harvest }
        #expect(lines.contains { $0.text.contains("60") && $0.text.contains("given back") })
    }

    // MARK: - What it is worth

    /// The point of the mechanic. A colony that goes into winter short of what
    /// it needs dies of it; the same colony, fed out of the crop its keeper
    /// took, sees spring.
    @Test("A fed colony that would have starved sees the spring")
    func feedingSavesAColony() {
        func wintering(seed: UInt64) -> Simulation {
            var simulation = Fixture.thrivingSimulation(config: .standard, seed: seed)
            simulation.setDay(Season.daysPerSeason * 3)
            simulation.mutateWorld { world in
                // A real winter cluster: winter-physiology bees and no brood,
                // which is what a colony actually goes into November with.
                // Jumping the clock alone leaves a nest full of summer bees,
                // and a summer bee dies of age within the fortnight however
                // much it is fed — which would have made this test about
                // longevity rather than about stores.
                var bees = world.hive.bees.filter { $0.kind == .queen }
                for index in 0..<140 {
                    bees.append(Bee(
                        id: EntityID(rawValue: UInt64(90_000 + index)),
                        kind: .worker,
                        stage: .adult,
                        daysInStage: 4,
                        patriline: UInt8(index % 12),
                        physiology: .winter
                    ))
                }
                world.hive.bees = bees

                // Well short of what that cluster will eat, with the crop of
                // the autumn just gone sitting in the bank.
                world.hive.resources = ResourcePool()
                world.hive.resources.add(30, of: .honey)
                world.honeyTaken = 900
            }
            return simulation
        }

        var starved = wintering(seed: 4_200)
        var fed = wintering(seed: 4_200)

        let short = fed.storesShortfall
        #expect(short > 0)
        #expect(abs(fed.feed(short) - short) < 0.001, "the bank and the comb both allow it")

        // The winter and the hungry gap after it, which is the span
        // `winterStoresRequired` actually provisions for: autumn through to
        // the first spring forage. The unfed colony sits at nothing for weeks
        // before it goes, which is what starving looks like from outside.
        for _ in 0..<(Season.daysPerSeason + 30) {
            _ = starved.stepDay()
            _ = fed.stepDay()
        }

        #expect(starved.hive.adultWorkerCount <= 5, "30 units is not a winter")
        #expect(fed.hive.adultWorkerCount > 5, "fed, it should come through")
        #expect(fed.hive.resources[.honey] > 0, "and come through with something left")
    }

    // MARK: - Determinism

    /// Feeding is a player action, not a system: it draws nothing from the
    /// random stream. Two identical colonies fed identically stay identical,
    /// which is also what makes the balance baseline reproducible.
    @Test("Two colonies fed the same way stay identical")
    func determinism() {
        var first = banked(honey: 40, bank: 300, seed: 4_300)
        var second = banked(honey: 40, bank: 300, seed: 4_300)
        #expect(first == second)

        first.feed(120)
        second.feed(120)
        #expect(first == second)

        for _ in 0..<20 {
            _ = first.stepDay()
            _ = second.stepDay()
        }
        #expect(first == second, "feeding forked the random stream")
    }

    /// And the other half of the same rule: a colony nobody feeds is the
    /// colony it always was. Nothing about the mechanic runs on its own.
    @Test("Nobody feeding changes nothing")
    func instinctIsUntouched() {
        var left = Fixture.thrivingSimulation(config: .standard, seed: 4_400)
        var right = Fixture.thrivingSimulation(config: .standard, seed: 4_400)
        right.mutateWorld { $0.honeyTaken = 500 }

        for _ in 0..<30 {
            _ = left.stepDay()
            _ = right.stepDay()
        }

        #expect(left.hive.resources[.honey] == right.hive.resources[.honey])
        #expect(left.hive.population == right.hive.population)
        #expect(abs(right.world.honeyTaken - 500) < 0.001, "no system spends the bank")
    }
}
