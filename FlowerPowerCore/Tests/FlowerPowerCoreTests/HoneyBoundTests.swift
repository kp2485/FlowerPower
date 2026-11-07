import Testing
import Foundation
@testable import FlowerPowerCore

/// A colony whose comb is full of honey, and what it does about it.
///
/// Until 2026-09-24 it did nothing. Every free cell was one pool, the
/// foragers filled it through the day, and the queen — who lays once a day —
/// got what they left, which in a flow was nothing. 95 of 200 gentle colonies
/// dwindled to nothing in their second summer with thousands of units of
/// honey in the comb. Three things were missing, and each has a test here:
/// the brood nest is not storage (`QueenSystem.broodNestRoom`), older bees
/// nurse when nobody younger can (`Hive.workforce(for:)`), and a swarm cell
/// has to be reared from brood.
@Suite("Honey-bound")
struct HoneyBoundTests {

    /// Early summer: laying near its peak, forage in bloom.
    private let summerDay = Season.daysPerSeason + 20

    /// A small colony on a full comb in a flow.
    ///
    /// 160 workers of every age, a mated queen, 340 cells drawn in a cavity
    /// of 340 so there is nowhere to build, and every cell holding honey or
    /// pollen. Six clover stands at 200 m so the flow is real rather than
    /// asserted. More honey than the winter needs, which is the case the brood
    /// nest is kept in.
    private func honeyBoundColony(seed: UInt64 = 8919, day: Int? = nil) -> Simulation {
        var simulation = Fixture.barrenSimulation(seed: seed)
        // The clock moves before the photographs, because a stand fades from
        // the day it was photographed.
        simulation.setDay(day ?? summerDay)
        for index in 0..<6 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "honey-bound-\(index)",
                species: Fixture.clover,
                confidence: 1,
                takenAt: epoch
            )
            simulation.setDistance(200, forPatchAt: index)
        }
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 300, droneCells: 40, capacity: 340)
            world.hive.bees.removeAll { $0.kind != .queen }
            for index in 0..<160 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(810_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: index % 40
                ))
            }
            // Bread bins full — past `minimumPollenReserve` — so the pollen
            // foragers stay home and what competes for a freed cell is
            // nectar. Pollen is not held out of the brood nest, and a colony
            // short of it fills the cells it eats clear with pollen first.
            world.hive.resources = ResourcePool([.pollen: 90])
            let room = Double(world.hive.freeCells) * ResourceKind.honey.unitsPerCell
            world.hive.resources.add(room, of: .honey)
        }
        simulation.simulateNectarFlow()
        return simulation
    }

    @Test("A full comb with a laying queen in a flow frees cells within a fortnight")
    func fullCombFreesCells() {
        var simulation = honeyBoundColony()
        #expect(simulation.hive.hasLayingQueen)
        #expect(simulation.hive.freeCells == 0)
        #expect(simulation.hive.resources.edibleEnergy > simulation.hive.winterStoresRequired)

        let report = simulation.runDays(14)

        // The cells the colony ate clear went to the queen rather than back to
        // the foragers. On 2026-09-24 this colony laid 9 eggs and held 16
        // cells as brood or kept empty for her; with the brood nest treated as
        // storage, as it was before, it laid none and held none — every cell
        // it ate clear was refilled with nectar before she could reach it.
        // The bounds are half of what it does, so they fail only on the old
        // behaviour or something like it.
        #expect(report.eggsLaid >= 5,
                "the queen laid \(report.eggsLaid) eggs in a fortnight on a full comb")
        #expect(simulation.hive.broodCount + simulation.hive.freeCells >= 7)
    }

    @Test("The brood nest never takes the room the larder still needs")
    func larderComesFirst() {
        var simulation = honeyBoundColony()
        // Empty the comb and leave the colony far short of its winter needs.
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.honey: 20, .pollen: 30])
        }
        let hive = simulation.hive
        let short = hive.winterStoresRequired - hive.resources.edibleEnergy
        let larderCells = Int((short / ResourceKind.honey.unitsPerCell).rounded(.up))
        #expect(larderCells > 0)

        let room = QueenSystem.broodNestRoom(
            in: hive, config: simulation.config, day: simulation.day
        )
        #expect(room <= max(0, hive.freeCells - larderCells))
    }

    @Test("A queenless colony keeps no brood nest")
    func queenlessKeepsNothing() {
        var simulation = honeyBoundColony()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.resources = ResourcePool([.honey: 400])
        }
        #expect(QueenSystem.broodNestRoom(
            in: simulation.hive, config: simulation.config, day: simulation.day
        ) == 0)
    }

    @Test("Older bees nurse when there is not one nurse, and only then")
    func houseBeesRevert() {
        func hive(ages: [Int]) -> Hive {
            var hive = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 1
            ).hive
            hive.bees = ages.enumerated().map { index, age in
                Bee(
                    id: EntityID(rawValue: UInt64(820_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: age
                )
            }
            return hive
        }

        // House bees alone, and foragers alone: the share of them that would
        // have been nursing in an ordinary colony nurses — nine days of the
        // table's forty-two.
        let share = 9.0 / 42.0
        #expect(abs(hive(ages: [14, 15, 16]).workforce(for: .nurseBee) - 3 * share) < 1e-9)
        let foragers = hive(ages: [25, 30, 35, 36, 40, 41, 41])
        #expect(abs(foragers.workforce(for: .nurseBee) - 7 * share) < 1e-9)
        // And are not taken off the flowers to do it.
        #expect(abs(foragers.workforce(for: .foragingBee) - 7) < 1e-9)
        // One real nurse among them: she is the whole nursing force, exactly
        // as before.
        let mixed = hive(ages: [5, 14, 15, 30])
        #expect(mixed.workforce(for: .nurseBee) == mixed.bees[0].effectiveness)
        // Nobody at all is nobody.
        #expect(hive(ages: []).workforce(for: .nurseBee) == 0)
    }

    @Test("A broodless colony starts no swarm cells, however full the comb")
    func broodlessColonyCannotSwarm() {
        func swarmCellsStarted(withEggs: Bool) -> Int {
            // Late spring, in the swarm season, with the queen's signal weak
            // and the colony well over the swarming size.
            var simulation = honeyBoundColony(day: Season.daysPerSeason - 10)
            simulation.mutateWorld { world in
                world.hive.pheromones.queenMandibular = 0
                if withEggs {
                    for index in 0..<10 {
                        world.hive.bees.append(Bee(
                            id: EntityID(rawValue: UInt64(830_000 + index)),
                            kind: .worker, stage: .egg
                        ))
                    }
                }
            }
            simulation.simulateNectarFlow()

            var started = 0
            for attempt in 0..<40 {
                var world = simulation.world
                var context = TickContext(
                    clock: simulation.clock, config: simulation.config,
                    rng: SeededRandom(seed: UInt64(attempt + 1)), ids: IDGenerator()
                )
                #expect(context.isDayBoundary)
                QueenSystem().update(&world, &context)
                started += world.hive.comb.queenCells.filter { $0.purpose == .swarm }.count
            }
            return started
        }

        #expect(swarmCellsStarted(withEggs: false) == 0)
        // And the same colony with eggs does, so the test is not passing
        // because nothing could ever swarm.
        #expect(swarmCellsStarted(withEggs: true) > 0)
    }

    @Test("Two identical honey-bound colonies stay identical")
    func deterministic() {
        var first = honeyBoundColony(seed: 24)
        var second = honeyBoundColony(seed: 24)
        first.runDays(30)
        second.runDays(30)
        #expect(first == second)
        #expect(first.hive.population > 0, "nothing survived, so this proved little")
    }
}
