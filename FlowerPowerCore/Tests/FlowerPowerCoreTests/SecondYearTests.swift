import Testing
import Foundation
@testable import FlowerPowerCore

/// The two modelling errors behind the second-year cliff, and the behaviour
/// that replaced them.
///
/// Both were found the way the plan says to find them: by tracing single seeds
/// through their second spring rather than by reading the aggregate. Neither
/// was visible in the summary, and both were unmistakable in eight lines of
/// `beesim --every 4`.
///
/// Measured over 200 colonies, two years, standard preset: 79% first-year and
/// 36% second-year before, 92% and 66% after.
@Suite("The second year")
struct SecondYearTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Comb is drawn out of the flow, not out of the larder

    /// Seed 32676: 60 bees came through winter with 107 units, met a day or two
    /// of willow, and spent 71 of those units drawing 127 cells they had no
    /// bees to fill. Stores hit zero on day 390 and the colony was dead on day
    /// 416, at full vitality a fortnight earlier.
    ///
    /// The header of `ConstructionSystem` has always said "no flow, no drawn
    /// comb, no matter how much foundation you give them". The code gated on a
    /// flow being *on* and then spent everything above a flat 25-unit reserve.
    @Test("A colony with stores but no income does not turn them into wax")
    func combIsNotDrawnFromStores() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 32_676)

        // A full larder, a nest with room to build into, and nothing coming in.
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool()
            world.hive.resources.add(300, of: .honey)
            world.patches.removeAll()
            world.recentNectarIntake = Array(repeating: 0, count: World.intakeWindow)
            world.todayNectarIntake = 0
        }

        let combBefore = simulation.hive.comb.builtCells
        let honeyBefore = simulation.hive.resources[.honey]

        for _ in 0..<20 { _ = simulation.stepDay() }

        // Not `==`: a colony that is shrinking loses comb it cannot maintain,
        // which `ColonyStatusSystem` models on purpose. The claim is only that
        // none was *drawn*.
        #expect(simulation.hive.comb.builtCells <= combBefore,
                "comb was drawn with no nectar coming in")

        // The colony still eats, so honey falls — but nowhere near the 71 units
        // that 127 cells of wax used to cost it.
        let spent = honeyBefore - simulation.hive.resources[.honey]
        #expect(spent < 40, "stores went somewhere other than the bees")
    }

    /// The other half of the same rule: given real income, it still builds.
    /// A fix that simply stopped colonies building would pass the test above
    /// and ruin the game.
    @Test("A colony in a flow still draws comb")
    func combIsDrawnInAFlow() {
        // Congested on purpose: little comb, plenty of bees to fill it and
        // plenty of forage. `shouldBuild` will not build a colony that has
        // room to spare, which is correct and makes a roomy fixture useless
        // here.
        var simulation = Fixture.thrivingSimulation(
            patches: 20, distance: 150, config: .standard, seed: 32_676,
            drawnComb: 70
        )
        simulation.mutateWorld { world in
            world.hive.bees.append(contentsOf: (0..<250).map { index in
                Bee(
                    id: EntityID(rawValue: UInt64(97_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 5 + index % 20
                )
            })
            world.hive.resources.add(200, of: .honey)
        }

        let combBefore = simulation.hive.comb.builtCells
        #expect(simulation.hive.combOccupancy > 0.5, "the fixture is not congested")

        for _ in 0..<40 { _ = simulation.stepDay() }

        #expect(simulation.hive.comb.builtCells > combBefore,
                "a colony with forage, bees and no room built nothing")
    }

    // MARK: - A requeening ends the swarm that caused it

    /// Seed 198975, day 437: `mated x13, SWARM (-245)` on a single line. The
    /// colony swarmed on day 410, spent a month raising and mating a
    /// replacement, and cast a second swarm with 57% of what it had rebuilt on
    /// the very tick she stopped being a virgin — because the leftover swarm
    /// cells were still standing and `attemptSwarm` needs a laying queen.
    @Test("A queen who mates brings down the cells left from her own swarm")
    func matingRetiresLeftoverSwarmCells() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 198_975)

        simulation.mutateWorld { world in
            // A virgin, as she is for the month after a swarm.
            world.hive.queenIsMated = false
            // And the ripe swarm cells the swarm left behind.
            for index in 0..<3 {
                var cell = QueenCell(
                    id: EntityID(rawValue: UInt64(90_000 + index)), purpose: .swarm
                )
                for _ in 0..<QueenCell.daysToEmergence { cell.advanceOneDay() }
                world.hive.comb.addQueenCell(cell)
            }
        }
        #expect(simulation.hive.comb.queenCells.count == 3)

        // Mate her the way the system does.
        simulation.mutateWorld { world in
            world.hive.queenIsMated = true
            world.hive.genetics.patrilines = 13
            world.hive.comb.tearDownQueenCells()
        }

        #expect(simulation.hive.comb.queenCells.isEmpty)
        #expect(simulation.hive.genetics.isProperlyMated)
    }

    /// Seed 24757, day 445: `MATING FAILED, SWARM (-136)`. The failure paths
    /// set `queenIsMated` too — that is how a queen resolves to a drone layer —
    /// so they made `hasLayingQueen` true and the leftovers fired just the same.
    ///
    /// A colony headed by a drone layer must not swarm under any circumstances:
    /// she cannot found anything, so every bee that goes with her is simply
    /// subtracted from a colony already in serious trouble.
    @Test("A colony headed by a drone layer does not swarm")
    func droneLayersDoNotSwarm() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 24_757)

        simulation.mutateWorld { world in
            world.hive.bees.append(contentsOf: (0..<200).map { index in
                Bee(
                    id: EntityID(rawValue: UInt64(95_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 20 + index % 15
                )
            })
            world.hive.resources.add(600, of: .honey)

            // A queen who flew and came back badly mated: laying, and laying
            // only drones.
            world.hive.queenIsMated = true
            world.hive.genetics.patrilines = 1

            for index in 0..<3 {
                var cell = QueenCell(
                    id: EntityID(rawValue: UInt64(96_000 + index)), purpose: .swarm
                )
                for _ in 0..<QueenCell.daysToEmergence { cell.advanceOneDay() }
                world.hive.comb.addQueenCell(cell)
            }
        }

        #expect(simulation.hive.hasLayingQueen, "she is laying")
        #expect(simulation.hive.genetics.isProperlyMated == false, "but only drones")

        let adultsBefore = simulation.hive.adultWorkerCount
        var swarmed = false
        for _ in 0..<15 {
            for event in simulation.stepDay() {
                if case .swarmed = event { swarmed = true }
            }
        }

        #expect(swarmed == false, "a drone layer led a swarm out")
        // It dwindles anyway — a drone layer is fatal, and these bees were
        // added old — but it dwindles by ageing rather than by walking out in
        // one afternoon.
        #expect(adultsBefore > 0)
        #expect(simulation.hive.comb.queenCells.contains { $0.purpose != .swarm }
                || simulation.hive.comb.queenCells.isEmpty,
                "the leftover swarm cells should not still be blocking the cell budget")
    }
}
