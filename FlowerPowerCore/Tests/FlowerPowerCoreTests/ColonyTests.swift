import XCTest
@testable import FlowerPowerCore

/// Thermoregulation, the queen's lifecycle, disease and defence.
final class ThermoregulationTests: XCTestCase {

    /// The original engine only ever cooled, so the brood nest drifted to
    /// ambient and the brood chilled to death in spring.
    func testColonyHoldsBroodNestWarmAgainstColdWeather() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.resources.add(500, of: .honey)
            // Enough bees to actually generate heat.
            for index in 0..<180 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(10_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 5
                ))
            }
            world.hive.bees.append(Bee(id: EntityID(rawValue: 500_001), kind: .worker, stage: .larva))
        }

        for _ in 0..<(3 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather(sky: .cloudy, temperature: 4)
        }

        XCTAssertGreaterThan(
            simulation.hive.temperatureCelsius, 30,
            "the brood nest was allowed to drift to ambient"
        )
    }

    func testColonyCoolsItselfInHeat() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.resources.add(200, of: .water)
            world.hive.resources.add(200, of: .honey)
            for index in 0..<150 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(15_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 14
                ))
            }
            world.hive.temperatureCelsius = 44
            world.hive.bees.append(Bee(id: EntityID(rawValue: 500_002), kind: .worker, stage: .larva))
        }

        for _ in 0..<24 {
            _ = simulation.step()
            simulation.forceWeather(sky: .clear, temperature: 38)
        }

        XCTAssertLessThan(simulation.hive.temperatureCelsius, 44)
    }

    /// Heating is fuelled by honey. A colony with no stores cannot hold
    /// temperature however many bees it has — this is how colonies die in
    /// winter with comb still in the hive.
    func testHeatingRequiresHoney() {
        func finalTemperature(honey: Double) -> Double {
            var simulation = Fixture.barrenSimulation()
            simulation.mutateWorld { world in
                world.hive.resources = ResourcePool([.honey: honey])
                for index in 0..<120 {
                    world.hive.bees.append(Bee(
                        id: EntityID(rawValue: UInt64(20_000 + index)),
                        kind: .worker, stage: .adult, daysInStage: 6
                    ))
                }
                world.hive.bees.append(Bee(id: EntityID(rawValue: 90_001), kind: .worker, stage: .larva))
                world.hive.temperatureCelsius = 35
            }

            for _ in 0..<(2 * SimClock.ticksPerDay) {
                _ = simulation.step()
                simulation.forceWeather(sky: .clear, temperature: -5)
            }
            return simulation.hive.temperatureCelsius
        }

        XCTAssertGreaterThan(finalTemperature(honey: 800), finalTemperature(honey: 0) + 3)
    }

    func testBroodlessColonyRunsCooler() {
        var simulation = Fixture.barrenSimulation()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.honey: 600])
            world.hive.bees.removeAll { $0.isBrood }
            for index in 0..<100 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(30_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 6
                ))
            }
            world.hive.bees.removeAll { $0.kind == .queen }
        }

        for _ in 0..<(3 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather(sky: .clear, temperature: 2)
        }

        // A broodless winter cluster does not pay to hold 35C.
        XCTAssertLessThan(simulation.hive.temperatureCelsius, 32)
    }

    func testBetterInsulatedSiteCostsLessHoney() {
        func honeyLeft(_ type: HiveLocationType) -> Double {
            var simulation = Fixture.barrenSimulation()
            simulation.mutateWorld { world in
                world.hive.location = HiveLocation(type: type)
                world.hive.resources = ResourcePool([.honey: 400])
                for index in 0..<120 {
                    world.hive.bees.append(Bee(
                        id: EntityID(rawValue: UInt64(40_000 + index)),
                        kind: .worker, stage: .adult, daysInStage: 6
                    ))
                }
                world.hive.bees.append(Bee(id: EntityID(rawValue: 95_001), kind: .worker, stage: .larva))
            }
            for _ in 0..<(5 * SimClock.ticksPerDay) {
                _ = simulation.step()
                simulation.forceWeather(sky: .clear, temperature: -2)
            }
            return simulation.hive.resources[.honey]
        }

        XCTAssertGreaterThan(honeyLeft(.cave), honeyLeft(.underTreeBranch))
    }
}

final class QueenLifecycleTests: XCTestCase {

    func testQueenLaysAndColonyGrows() {
        var simulation = Fixture.thrivingSimulation(patches: 18, distance: 200)
        simulation.forceWeather()
        let start = simulation.hive.population

        // A founding colony grows slowly at first: brood is capped by the
        // handful of nurses it has, and each of those takes three weeks to
        // replace. A fortnight is not long enough to see the curve turn.
        simulation.runDays(30)

        XCTAssertGreaterThan(simulation.hive.population, start)
        XCTAssertGreaterThan(simulation.hive.broodCount, 0)
    }

    func testQueenlessColonyLaysNothing() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.bees.removeAll { $0.isBrood }
        }

        simulation.runDays(3)
        XCTAssertEqual(simulation.hive.count(kind: .worker, stage: .egg), 0)
    }

    func testQueenStopsLayingWhenStarving() {
        var simulation = Fixture.barrenSimulation()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool()
            world.hive.bees.removeAll { $0.isBrood }
        }

        simulation.runDays(3)
        XCTAssertEqual(simulation.hive.broodCount, 0)
    }

    func testQueenStopsLayingInAColdNest() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.isBrood }
            world.hive.temperatureCelsius = 20
            world.hive.resources.add(300, of: .honey)
        }
        // Strip the workforce so nothing can warm the nest back up.
        simulation.mutateWorld { $0.hive.bees.removeAll { $0.kind == .worker } }

        simulation.runDays(2)
        XCTAssertEqual(simulation.hive.count(kind: .worker, stage: .egg), 0)
    }

    /// A queenless colony with young brood raises an emergency queen.
    func testQueenlessColonyRaisesAnEmergencyQueen() {
        var simulation = Fixture.thrivingSimulation(patches: 18, distance: 200)
        simulation.forceWeather()
        simulation.runDays(6)   // build up some young brood

        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.resources.add(200, of: .honey)
            world.hive.resources.add(60, of: .wax)
        }

        var sawQueenCell = false
        for _ in 0..<(10 * SimClock.ticksPerDay) {
            for event in simulation.step() {
                if case .queenCellStarted(.emergency) = event { sawQueenCell = true }
            }
            simulation.forceWeather()
        }

        XCTAssertTrue(sawQueenCell, "a queenless colony with brood never tried to replace her")
    }

    /// A colony queenless too long, with no brood left, develops laying workers
    /// and is finished.
    func testHopelesslyQueenlessColonyDevelopsLayingWorkers() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.bees.removeAll { $0.isBrood }
            world.hive.daysQueenless = 30
            world.hive.resources.add(200, of: .honey)
        }

        simulation.runDays(2)
        XCTAssertTrue(simulation.hive.hasLayingWorkers)
    }

    func testVirginQueenCannotLay() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.isBrood }
            world.hive.queenIsMated = false
            world.hive.resources.add(300, of: .honey)
        }

        XCTAssertTrue(simulation.hive.hasVirginQueen)
        XCTAssertFalse(simulation.hive.hasLayingQueen)

        // One day, before she is old enough to fly.
        simulation.runDays(1)
        XCTAssertEqual(simulation.hive.count(kind: .worker, stage: .egg), 0)
    }

    func testVirginQueenMatesInGoodWeather() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.bees.append(Bee(
                id: EntityID(rawValue: 600_001),
                kind: .queen, stage: .adult, daysInStage: 7
            ))
            world.hive.queenIsMated = false
            world.hive.resources.add(300, of: .honey)
        }

        var mated = false
        for _ in 0..<(8 * SimClock.ticksPerDay) {
            for event in simulation.step() {
                if case .queenMated = event { mated = true }
            }
            simulation.forceWeather(sky: .clear, temperature: 26)
        }

        XCTAssertTrue(mated || simulation.hive.queenIsMated, "the queen never managed a mating flight")
    }

    func testPoorlyMatedQueenIsFlaggedUnviable() {
        let poor = QueenGenetics(patrilines: 1)
        XCTAssertFalse(poor.isProperlyMated)
        XCTAssertLessThan(poor.geneticDiversity, 0.2)

        let good = QueenGenetics(patrilines: 18)
        XCTAssertTrue(good.isProperlyMated)
        XCTAssertGreaterThan(good.geneticDiversity, 0.8)
    }

    func testGeneticDiversityImprovesDiseaseResistance() {
        let inbred = QueenGenetics(patrilines: 2, hygienicBehaviour: 0.5)
        let diverse = QueenGenetics(patrilines: 20, hygienicBehaviour: 0.5)
        XCTAssertGreaterThan(diverse.diseaseResistance, inbred.diseaseResistance)
    }

    // MARK: - Pheromones

    /// The queen's signal is diluted by colony size — which is exactly why big
    /// colonies swarm even with a perfectly good queen.
    func testQueenPheromoneIsDilutedByColonySize() {
        func settledSignal(adults: Int) -> Double {
            var simulation = Fixture.barrenSimulation()
            simulation.mutateWorld { world in
                world.hive.resources = ResourcePool([.honey: 500])
                for index in 0..<adults {
                    world.hive.bees.append(Bee(
                        id: EntityID(rawValue: UInt64(70_000 + index)),
                        kind: .worker, stage: .adult, daysInStage: 8
                    ))
                }
            }
            for _ in 0..<(6 * SimClock.ticksPerDay) { _ = simulation.step() }
            return simulation.hive.pheromones.queenMandibular
        }

        XCTAssertGreaterThan(settledSignal(adults: 10), settledSignal(adults: 600))
    }

    func testQueenSignalCollapsesWhenSheIsGone() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(3)
        let withQueen = simulation.hive.pheromones.queenMandibular

        simulation.mutateWorld { $0.hive.bees.removeAll { $0.kind == .queen } }
        simulation.runDays(5)

        XCTAssertLessThan(simulation.hive.pheromones.queenMandibular, withQueen)
    }
}

final class DiseaseTests: XCTestCase {

    /// Varroa can only breed in capped brood, so a broodless colony is the one
    /// natural check on the mite.
    func testVarroaNeedsCappedBroodToGrow() {
        func growth(withBrood: Bool) -> Double {
            var simulation = Fixture.barrenSimulation()
            simulation.mutateWorld { world in
                world.hive.resources = ResourcePool([.honey: 400, .pollen: 100])
                world.hive.pathogens[.varroa] = 0.2
                world.hive.genetics = QueenGenetics(patrilines: 12, hygienicBehaviour: 0)
                world.hive.bees.removeAll { $0.isBrood }
                if withBrood {
                    for index in 0..<80 {
                        world.hive.bees.append(Bee(
                            id: EntityID(rawValue: UInt64(80_000 + index)),
                            kind: .worker, stage: .pupa, daysInStage: 1
                        ))
                    }
                }
            }
            simulation.runDays(20)
            return simulation.hive.pathogens[.varroa]
        }

        XCTAssertGreaterThan(growth(withBrood: true), growth(withBrood: false))
    }

    /// Above roughly a 3% mite load the virus takes off — and it is the virus,
    /// not the mite, that kills the colony.
    func testHighVarroaSeedsDeformedWingVirus() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.pathogens[.varroa] = PathogenLoad.varroaVirusThreshold + 0.2
            world.hive.resources.add(300, of: .honey)
        }

        simulation.runDays(3)
        XCTAssertGreaterThan(simulation.hive.pathogens[.deformedWingVirus], 0)
    }

    func testLowVarroaDoesNotSeedTheVirus() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.pathogens = PathogenLoad([.varroa: 0.05])
            world.hive.genetics = QueenGenetics(patrilines: 20, hygienicBehaviour: 0.9)
        }

        simulation.runDays(2)
        XCTAssertEqual(simulation.hive.pathogens[.deformedWingVirus], 0)
    }

    /// Hygienic behaviour is the colony's own immune system, and the single
    /// most valuable trait a breeder selects for.
    func testHygienicColoniesClearInfectionsFaster() {
        func remaining(hygiene: Double) -> Double {
            var simulation = Fixture.thrivingSimulation(seed: 8)
            simulation.mutateWorld { world in
                world.hive.pathogens = PathogenLoad([.chalkbrood: 0.5])
                world.hive.genetics = QueenGenetics(patrilines: 12, hygienicBehaviour: hygiene)
                world.hive.resources.add(400, of: .honey)
            }
            simulation.runDays(20)
            return simulation.hive.pathogens[.chalkbrood]
        }

        XCTAssertLessThan(remaining(hygiene: 0.95), remaining(hygiene: 0.05))
    }

    /// Deformed wing virus produces bees that physically cannot fly. They
    /// survive in the hive and never forage, which is how an infested colony
    /// starves with a full nest of bees.
    func testDamagedBeesCannotForage() {
        var healthy = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 25)
        XCTAssertTrue(healthy.canFly)
        XCTAssertTrue(healthy.performs(.foragingBee))

        healthy.damage(0.8)
        XCTAssertFalse(healthy.canFly)
        XCTAssertFalse(healthy.performs(.foragingBee), "a flightless bee is still being sent out")
    }

    func testDamagedBeesStillDoInsideWork() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 5)
        bee.damage(0.9)

        XCTAssertFalse(bee.canFly)
        XCTAssertTrue(bee.performs(.nurseBee), "a flightless bee can still nurse")
    }

    func testPathogenLoadSaturatesRatherThanSumming() {
        let load = PathogenLoad([.varroa: 0.5, .nosema: 0.5, .chalkbrood: 0.5])
        XCTAssertLessThan(load.totalPressure, 1.0)
        XCTAssertGreaterThan(load.totalPressure, 0.5)
    }

    func testDominantPathogenIsReported() {
        let load = PathogenLoad([.varroa: 0.2, .nosema: 0.7])
        XCTAssertEqual(load.dominant?.pathogen, .nosema)
    }
}

final class DefenceTests: XCTestCase {

    /// A bear is unstoppable no matter how well defended the colony is.
    func testCatastrophicPredatorsCannotBeRepelled() {
        for predator in [Predator.bear, .badger, .human] {
            XCTAssertEqual(predator.threatLevel, 1.0)
            XCTAssertFalse(predator.isDeterredByGuards)
        }
    }

    /// Field ambushers eat foragers out at the flowers, where guards cannot help.
    func testFieldPredatorsAreNotDeterredByGuards() {
        for predator in [Predator.crabSpider, .dragonfly, .beeEater] {
            XCTAssertEqual(predator.attackStyle, .field)
            XCTAssertFalse(predator.isDeterredByGuards)
        }
    }

    func testGuardsDeterEntranceRaiders() {
        for predator in [Predator.wasp, .robberBee, .skunk] {
            XCTAssertTrue(predator.isDeterredByGuards)
        }
    }

    /// An exposed site is indefensible however many guards it posts.
    func testExposedSitesAreHarderToDefend() {
        XCTAssertLessThan(
            HiveLocationType.underTreeBranch.defensibility,
            HiveLocationType.insideWalls.defensibility
        )
    }

    func testWeakColoniesAttractOpportunists() {
        for predator in [Predator.waxMoth, .hiveBeetle, .mouse, .robberBee] {
            XCTAssertTrue(predator.exploitsWeakColonies)
        }
    }

    /// Over a long run, a well-defended strong colony should fare better than a
    /// weak one in an exposed site.
    /// Measured as the share of attacks the colony *repels*, which is what
    /// `defensibility` actually decides in `attemptDefence`.
    ///
    /// This used to count predation deaths and assert that a good site had
    /// fewer. That passed for the wrong reason and eventually stopped passing
    /// at all: deaths are dominated by how long the colony lives, not by how
    /// well it holds the door. An indefensible site kills its colony, and a
    /// dead colony is not raided — so the numbers came out as 251 predation
    /// deaths in a wall cavity against 94 under an open branch, which reads as
    /// defensibility working backwards and is really survivorship.
    ///
    /// The repel rate has no such confound, and it separates the sites
    /// cleanly: 38% behind a wall, 35% in a tree, 15% on a cliff face, 4% on
    /// open comb hanging from a branch.
    func testGoodSitesRepelMoreOfWhatComes() {
        func repelRate(location: HiveLocationType, seed: UInt64) -> (attacks: Int, repelled: Int) {
            var simulation = Fixture.thrivingSimulation(seed: seed, locationType: location)
            simulation.mutateWorld { world in
                world.hive.resources.add(600, of: .honey)
                for index in 0..<250 {
                    world.hive.bees.append(Bee(
                        id: EntityID(rawValue: UInt64(200_000 + index)),
                        kind: .worker, stage: .adult, daysInStage: 19
                    ))
                }
            }
            var attacks = 0
            var repelled = 0
            for _ in 0..<200 {
                for event in simulation.stepDay() {
                    if case .attacked = event { attacks += 1 }
                    if case .attackRepelled = event { repelled += 1 }
                }
            }
            return (attacks, repelled)
        }

        // One colony's luck proves nothing — a single bear swamps the signal —
        // so pool across several seeds.
        let seeds: [UInt64] = [12, 77, 314, 1_618, 2_718]

        func pooled(_ location: HiveLocationType) -> Double {
            let totals = seeds.reduce(into: (0, 0)) { running, seed in
                let outcome = repelRate(location: location, seed: seed)
                running.0 += outcome.attacks
                running.1 += outcome.repelled
            }
            XCTAssertGreaterThan(totals.0, 20, "too few attacks at \(location) to measure anything")
            return Double(totals.1) / Double(totals.0)
        }

        let wall = pooled(.insideWalls)
        let branch = pooled(.underTreeBranch)

        XCTAssertGreaterThan(
            wall, branch,
            "site defensibility is not affecting whether attacks are repelled"
        )
        // And by a margin worth having, not a rounding difference. An open
        // branch nest is meant to be genuinely indefensible.
        XCTAssertGreaterThan(wall, branch * 2)
    }
}
