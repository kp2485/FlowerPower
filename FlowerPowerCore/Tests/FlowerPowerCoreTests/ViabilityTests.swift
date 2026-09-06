import XCTest
@testable import FlowerPowerCore

/// Long-run colony behaviour.
///
/// These are the tests that actually protect the balance. Every one of them
/// corresponds to a failure found by running the engine for a simulated year
/// and watching what killed the colony — the sort of bug unit tests never
/// catch, because each individual system was behaving exactly as written.
final class ViabilityTests: XCTestCase {

    /// Runs a colony for a year with a player who keeps photographing flowers.
    private func runYear(
        seed: UInt64,
        days: Int = 400,
        patches: Int = 12,
        config: SimulationConfig = .standard
    ) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            config: config,
            seed: seed
        )

        func stock(_ count: Int, tag: String) {
            for index in 0..<count {
                simulation.registerPhotograph(
                    photoLocalIdentifier: "\(tag)-\(index)",
                    species: Fixture.palette[index % Fixture.palette.count],
                    confidence: 0.9,
                    coordinate: nil,
                    takenAt: epoch,
                    distanceMetres: 400
                )
            }
        }

        stock(patches, tag: "start")

        for day in 0..<days {
            _ = simulation.stepDay()
            if day % 45 == 0 && day > 0 {
                simulation.pruneDepletedPatches()
                stock(max(1, patches / 3), tag: "d\(day)")
            }
            if simulation.hive.bees.isEmpty { break }
        }

        return simulation
    }

    // MARK: - The second year

    /// The second year is harder than the first, and it is meant to be — but
    /// it used to be harder than anything in the model justified.
    ///
    /// Measured across 60 trials, survival fell from 75% at day 400 to 25% at
    /// day 460. A sixty-day window taking two colonies in three is not
    /// attrition, it is an event, so it was traced rather than tuned. Three
    /// things turned out to be wrong, all of them in how the colony handles
    /// its queen, and none of them findable from unit tests:
    ///
    /// 1. **Swarming out of winter.** There was a rule ending swarm season but
    ///    none starting it, so a colony could divide on spring day 16, halving
    ///    itself while still living on the last of its stores. Real swarming
    ///    is the product of the build-up, not its opening move.
    /// 2. **Swarming with no queen to send.** A swarm is the old queen leaving
    ///    with the bees, but the test for it only asked whether queen
    ///    pheromone was weak — which is trivially true of a colony that has
    ///    just swarmed and is therefore queenless. Colonies swarmed twice in
    ///    ten days on the strength of their own queenlessness.
    /// 3. **Superseding virgins.** `isProperlyMated` is false for a queen who
    ///    has not mated *at all*, so a colony read every newly emerged virgin
    ///    as a failing queen and replaced her within days, over and over,
    ///    burning the worker eggs it needed to raise any queen at all.
    ///
    /// Fixing those took two-year survival from 15% to 25% without moving the
    /// first year (75%), and left swarming at about one per colony per two
    /// years, which is in the real range — not every colony swarms every year.
    ///
    /// What the cliff is *not*, all measured: not disease (turning pathogen
    /// arrival off moves two-year survival by two points), not forage
    /// (twenty-four patches restocked every fifteen days gives 13%), not
    /// winter provisioning (the margin from 1.0 to 1.45 stays inside 7-15%).
    /// The standing hypothesis had been that varroa crossed the
    /// deformed-wing-virus threshold in the second season. It does not.
    ///
    /// What remains is real: a colony that divides, requeens, and stakes
    /// itself on a mating flight each time will not last indefinitely, and an
    /// unmanaged one dying in its second or third year is what happens. The
    /// test pins the shape rather than the number.
    func testTheSecondYearIsHarderThanTheFirstButNotImpossible() {
        let seeds: [UInt64] = [1_000, 8_919, 16_838, 24_757,
                               32_676, 40_595, 48_514, 56_433]

        func survivors(days: Int) -> Int {
            seeds.filter { runYear(seed: $0, days: days).hive.adultWorkerCount > 5 }.count
        }

        let firstYear = survivors(days: 400)
        let secondYear = survivors(days: 760)

        XCTAssertGreaterThan(
            firstYear, secondYear,
            "the second year should cost colonies; if it stops doing so, "
            + "swarming or requeening has quietly been defanged"
        )
        XCTAssertGreaterThanOrEqual(
            secondYear, 1,
            "some colony should get through two years — at zero the game has "
            + "no long game at all"
        )
    }

    /// Requeening is a normal event, not an exception, and that is precisely
    /// why the second year is dangerous: every one of these is a mating flight
    /// the colony might not come back from.
    func testAColonyReplacesItsQueenOverTwoYears() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 8_919
        )
        for index in 0..<12 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "q-\(index)",
                species: Fixture.palette[index % Fixture.palette.count],
                confidence: 0.9,
                coordinate: nil,
                takenAt: epoch,
                distanceMetres: 400
            )
        }

        var queensEmerged = 0
        for day in 0..<760 {
            for event in simulation.stepDay() {
                if case .queenEmerged = event { queensEmerged += 1 }
            }
            if day % 45 == 0, day > 0 {
                simulation.pruneDepletedPatches()
                for index in 0..<4 {
                    simulation.registerPhotograph(
                        photoLocalIdentifier: "r\(day)-\(index)",
                        species: Fixture.palette[index % Fixture.palette.count],
                        confidence: 0.9,
                        coordinate: nil,
                        takenAt: epoch,
                        distanceMetres: 400
                    )
                }
            }
            if simulation.hive.bees.isEmpty { break }
        }

        XCTAssertGreaterThan(
            queensEmerged, 0,
            "no queen was raised in two years, so swarming and supersedure "
            + "have both stopped happening"
        )
    }

    // MARK: - The headline result

    /// A colony that is kept supplied with forage should usually see out a
    /// year. "Usually" is the operative word — bears, failed mating flights and
    /// bad autumns are all real — so this measures a rate across seeds rather
    /// than demanding any single colony survive.
    func testMostColoniesSurviveTheirFirstYear() {
        let seeds: [UInt64] = [1_000, 8_919, 16_838, 24_757, 32_676,
                               40_595, 48_514, 56_433, 64_352, 72_271]

        let survivors = seeds.filter { seed in
            let simulation = runYear(seed: seed)
            return simulation.hive.adultWorkerCount > 5
        }

        XCTAssertGreaterThanOrEqual(
            survivors.count, 6,
            "only \(survivors.count)/10 colonies survived a year; the balance has regressed"
        )
    }

    /// And a colony given nothing to eat must die. The photo loop has to matter.
    func testColonyWithNoForageDies() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 4
        )

        for _ in 0..<200 {
            _ = simulation.stepDay()
            if simulation.hive.bees.isEmpty { break }
        }

        XCTAssertLessThan(
            simulation.hive.adultWorkerCount, 10,
            "a colony with no photographed flowers should not thrive"
        )
    }

    // MARK: - Growth

    func testColonyGrowsSubstantiallyOverASeason() {
        let simulation = runYear(seed: 1_000, days: 170)
        XCTAssertGreaterThan(
            simulation.hive.population, 80,
            "a well-fed colony should build up strongly through spring and summer"
        )
    }

    /// Regression: comb-building was unreachable because the congestion metric
    /// was multiplied by 0.6 whenever expansion room remained, capping it below
    /// the build threshold it was being compared against.
    func testColonyDrawsOutComb() {
        let simulation = runYear(seed: 1_000, days: 170)
        XCTAssertGreaterThan(
            simulation.hive.comb.builtCells, 150,
            "the colony never drew out any comb"
        )
    }

    /// Regression: `swarmPressure` had the same impossible-threshold bug, and
    /// forty test colonies produced exactly zero swarms.
    /// Regression: `swarmPressure` was multiplied by a flat factor whenever any
    /// expansion room remained, capping it below the threshold it was compared
    /// against. Forty test colonies produced exactly zero swarms.
    ///
    /// Swarming is what a colony does once it is genuinely crowded, which takes
    /// a full year of build-up — the trigger is the queen's pheromone thinning
    /// out across a large population, and a first-year colony never gets there.
    /// So this runs into a second spring, which is when real colonies swarm too.
    func testEstablishedColoniesSwarm() {
        var swarms = 0

        for seed in [UInt64(8_919), 1_000, 16_838, 24_757, 32_676, 40_595] {
            var simulation = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity),
                startingAt: epoch,
                config: .gentle,
                seed: seed
            )
            stockPatches(&simulation, count: 12, tag: "start")

            for day in 0..<400 {
                for event in simulation.stepDay() {
                    if case .swarmed = event { swarms += 1 }
                }
                if day % 45 == 0, day > 0 {
                    simulation.pruneDepletedPatches()
                    stockPatches(&simulation, count: 4, tag: "d\(day)")
                }
                if simulation.hive.bees.isEmpty { break }
            }

            // One is enough to prove the mechanic is reachable.
            if swarms > 0 { break }
        }

        XCTAssertGreaterThan(swarms, 0, "no colony ever swarmed; swarming is unreachable")
    }

    private func stockPatches(_ simulation: inout Simulation, count: Int, tag: String) {
        for index in 0..<count {
            simulation.registerPhotograph(
                photoLocalIdentifier: "\(tag)-\(index)",
                species: Fixture.palette[index % Fixture.palette.count],
                confidence: 0.9,
                coordinate: nil,
                takenAt: epoch,
                distanceMetres: 400
            )
        }
    }

    // MARK: - Overwintering

    /// Regression: autumn-reared bees died on a six-week summer clock, so every
    /// colony entered winter with a fraction of the cluster it needed.
    func testColonyRearsWinterBees() {
        let simulation = runYear(seed: 1_000, days: 250)   // late autumn

        let winterBees = simulation.hive.bees.filter {
            $0.kind == .worker && $0.isAdult && $0.physiology == .winter
        }
        XCTAssertGreaterThan(
            winterBees.count, 10,
            "the colony went into winter without rearing long-lived winter bees"
        )
    }

    /// Colonies should reach late autumn provisioned. Measured across seeds:
    /// any single colony may have had a bad year, and that is the point of the
    /// weather model.
    /// Ten seeds and the mean, rather than five and the median. Any change to
    /// how the random stream is consumed — a system that now rolls fewer dice
    /// a day, say — re-seeds every colony's year, and five colonies is not
    /// enough for a median to be a measurement. This failed at 169 against 200
    /// after threat sieges started blocking concurrent encounters, while the
    /// 60-trial mean in beesim sat at 316: a re-seeding, not a regression.
    func testColoniesBankStoresForWinter() {
        let seeds: [UInt64] = [1_000, 8_919, 16_838, 24_757, 32_676,
                               40_595, 48_514, 56_433, 64_352, 72_271]
        let stores = seeds
            .map { runYear(seed: $0, days: 250).hive.resources.edibleEnergy }

        let mean = stores.reduce(0, +) / Double(stores.count)
        XCTAssertGreaterThan(
            mean, 200,
            "colonies reached late autumn with little banked: \(stores.map { Int($0) })"
        )
    }

    /// Regression: a broodless nest cooled to the cluster temperature, the
    /// queen could not lay into a cold nest, and the colony was deadlocked out
    /// of ever rearing brood again.
    func testBroodlessColonyWarmsUpToResumeLaying() {
        var simulation = Fixture.thrivingSimulation(patches: 18, distance: 200)
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.isBrood }
            world.hive.temperatureCelsius = 20
            world.hive.resources.add(400, of: .honey)
            world.hive.resources.add(120, of: .pollen)
        }

        for _ in 0..<20 {
            _ = simulation.stepDay()
            simulation.forceWeather(sky: .clear, temperature: 18)
        }

        XCTAssertGreaterThan(
            simulation.hive.temperatureCelsius,
            simulation.config.minimumBroodTemperature,
            "the nest never warmed back up, so laying could never restart"
        )
        XCTAssertGreaterThan(simulation.hive.broodCount, 0, "the queen never resumed laying")
    }

    // MARK: - Queen succession

    /// Regression: a colony that lost its queen could not afford the one queen
    /// cell that would have saved it, because comb-building had spent every
    /// scrap of wax. Bees render wax from honey on demand.
    func testQueenlessColonyRearsAReplacementWithNoWaxInStore() {
        var simulation = Fixture.thrivingSimulation(patches: 18, distance: 200)

        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.resources[.wax] = 0
            world.hive.resources.add(300, of: .honey)
            world.hive.resources.add(80, of: .pollen)

            // Young brood to raise her from, stated outright rather than left to
            // whatever the colony happened to have built up.
            for index in 0..<12 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(950_000 + index)),
                    kind: .worker, stage: .larva, daysInStage: 1
                ))
            }
        }

        var startedCells = false
        for _ in 0..<12 {
            for event in simulation.stepDay() {
                if case .queenCellStarted = event { startedCells = true }
            }
            simulation.forceWeather()
        }

        XCTAssertTrue(startedCells, "the colony could not afford a queen cell and died with a full larder")
    }

    /// Regression: an autumn supersedure produced a virgin who could never mate
    /// — no drones, never warm enough — and blocked brood rearing until the
    /// colony starved at full strength.
    func testColoniesDoNotSupersedeWhenAReplacementCannotMate() {
        var simulation = Fixture.thrivingSimulation()
        // Late autumn, with a failing queen.
        simulation.clock = SimClock(epoch: epoch, tick: 250 * SimClock.ticksPerDay)
        simulation.mutateWorld { world in
            world.hive.resources.add(400, of: .honey)
            if let index = world.hive.bees.firstIndex(where: { $0.kind == .queen }) {
                world.hive.bees[index].damage(0.8)
            }
        }

        var supersedureCells = 0
        for _ in 0..<40 {
            for event in simulation.stepDay() {
                if case .queenCellStarted(.supersedure) = event { supersedureCells += 1 }
            }
        }

        XCTAssertEqual(
            supersedureCells, 0,
            "the colony requeened in autumn, where the new queen cannot possibly mate"
        )
    }

    /// Regression: a virgin past her mating window stayed a virgin forever,
    /// leaving the colony with a queen it could neither use nor replace.
    func testVirginPastHerWindowResolvesToADroneLayer() {
        var simulation = Fixture.thrivingSimulation()
        // Read the config out first: touching `simulation.config` inside the
        // mutating closure overlaps its exclusive access.
        let latestMatingDay = simulation.config.matingFlightLatestDay

        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            world.hive.bees.append(Bee(
                id: EntityID(rawValue: 900_001),
                kind: .queen, stage: .adult,
                daysInStage: latestMatingDay + 1
            ))
            world.hive.queenIsMated = false
        }

        _ = simulation.stepDay()

        XCTAssertFalse(
            simulation.hive.hasVirginQueen,
            "she is still an unmated virgin, and the colony is stuck"
        )
        XCTAssertFalse(simulation.hive.genetics.isProperlyMated)
    }

    // MARK: - Disease over the long run

    /// Regression: nosema had no recovery path at all, so it ratcheted to total
    /// infection and killed every colony in its second summer. Real colonies
    /// clear it once the bees can fly out and cleanse.
    func testNosemaClearsInGoodFlyingWeather() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.pathogens = PathogenLoad([.nosema: 0.6])
            world.hive.resources.add(400, of: .honey)
        }

        for _ in 0..<40 {
            _ = simulation.stepDay()
            simulation.forceWeather(sky: .clear, temperature: 22)
        }

        XCTAssertLessThan(
            simulation.hive.pathogens[.nosema], 0.3,
            "nosema never recedes, so it is a guaranteed death sentence"
        )
    }

    /// Varroa is the exception: it does not simply go away, and a colony with
    /// no hygienic behaviour should see the mite build.
    func testVarroaPersistsWithoutHygiene() {
        var simulation = Fixture.thrivingSimulation()
        simulation.mutateWorld { world in
            world.hive.pathogens = PathogenLoad([.varroa: 0.15])
            world.hive.genetics = QueenGenetics(patrilines: 12, hygienicBehaviour: 0.0)
            world.hive.resources.add(400, of: .honey)
        }

        simulation.runDays(60)

        XCTAssertGreaterThan(
            simulation.hive.pathogens[.varroa], 0.1,
            "varroa faded away on its own, which it does not do"
        )
    }

    // MARK: - Difficulty presets

    func testGentlePresetIsKinderThanHarsh() {
        func survivors(_ config: SimulationConfig) -> Int {
            [UInt64(1_000), 8_919, 16_838, 24_757, 32_676, 40_595].filter { seed in
                runYear(seed: seed, config: config).hive.adultWorkerCount > 5
            }.count
        }

        XCTAssertGreaterThanOrEqual(
            survivors(.gentle), survivors(.harsh),
            "the gentle preset is not actually gentler"
        )
    }
}
