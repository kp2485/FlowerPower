import XCTest
@testable import FlowerPowerCore

/// The resource economy. The first version of this engine produced
/// speculatively — nurses secreting royal jelly with no larvae, builders
/// burning honey into wax forever — which drained the stores to zero, stopped
/// the queen laying, and killed every colony. These tests exist to keep that
/// from coming back.
final class EconomyTests: XCTestCase {

    // MARK: - Demand-driven production

    func testNursesDoNotMakeRoyalJellyWithNoBrood() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather()
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.isBrood }
            world.hive.resources = ResourcePool([.honey: 200, .pollen: 200])
            // Remove the queen so no new brood appears during the test.
            world.hive.bees.removeAll { $0.kind == .queen }
        }

        for _ in 0..<20 { _ = simulation.step() }

        XCTAssertLessThan(
            simulation.hive.resources[.royalJelly], 5,
            "royal jelly is being stockpiled with no larvae to eat it"
        )
    }

    func testBuildersDoNotBurnHoneyWhenThereIsRoom() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.honey: 300])
            // Plenty of empty comb: no reason at all to build more.
            world.hive.comb = Comb(workerCells: 400, droneCells: 60, capacity: 700)
            world.hive.bees.removeAll { $0.isBrood }
        }

        let before = simulation.hive.resources[.honey]
        for _ in 0..<24 { _ = simulation.step() }
        let spent = before - simulation.hive.resources[.honey]

        XCTAssertLessThan(spent, before * 0.25, "honey is being burned into unnecessary wax")
    }

    /// Comb is only drawn during a flow, so the test has to supply one.
    func testColonyBuildsCombDuringAFlow() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather(temperature: 24)
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 40, droneCells: 4, capacity: 700)
            // Enough stores to fill that small comb, so it is short of room.
            world.hive.resources = ResourcePool([.honey: 150, .wax: 60])
        }
        simulation.simulateNectarFlow()

        let before = simulation.hive.comb.builtCells
        for _ in 0..<(4 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather(temperature: 24)
            simulation.simulateNectarFlow()
        }

        XCTAssertGreaterThan(simulation.hive.comb.builtCells, before)
    }

    /// And a colony that is not in a flow leaves the wax alone, however much
    /// honey it is sitting on.
    func testColonyDoesNotBuildCombOutsideAFlow() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather(temperature: 24)
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 40, droneCells: 4, capacity: 700)
            world.hive.resources = ResourcePool([.honey: 300, .wax: 60])
            world.recentNectarIntake = Array(repeating: 0, count: World.intakeWindow)
        }

        let before = simulation.hive.comb.builtCells
        for _ in 0..<(3 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.mutateWorld { world in
                world.recentNectarIntake = Array(repeating: 0, count: World.intakeWindow)
            }
        }

        XCTAssertEqual(simulation.hive.comb.builtCells, before)
    }

    func testCombNeverExceedsSiteCapacity() {
        var simulation = Fixture.thrivingSimulation(locationType: .underTreeBranch)
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.honey: 5_000, .wax: 5_000])
        }

        simulation.runDays(30)
        XCTAssertLessThanOrEqual(simulation.hive.comb.builtCells, simulation.hive.maximumCells)
    }

    // MARK: - Honey solvency

    /// The regression that matters most: a colony with steady forage must not
    /// drain itself to zero honey.
    func testWellFedColonyKeepsHoneyInStore() {
        var simulation = Fixture.thrivingSimulation(patches: 20, distance: 200)
        simulation.forceWeather()

        var minimumHoney = Double.infinity
        for _ in 0..<(25 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather()
            minimumHoney = min(minimumHoney, simulation.hive.resources[.honey])
        }

        XCTAssertGreaterThan(minimumHoney, 0, "the colony ran completely out of honey")
        XCTAssertGreaterThan(simulation.hive.resources.edibleEnergy, 20)
    }

    func testNectarRipensIntoHoney() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather(humidity: 0.2)
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.nectar: 100, .honey: 50])
        }

        let nectarBefore = simulation.hive.resources[.nectar]
        simulation.runUntilHour(2)
        for _ in 0..<6 { _ = simulation.step() }

        XCTAssertLessThan(simulation.hive.resources[.nectar], nectarBefore)
    }

    func testHumidityStallsRipening() {
        func honeyMade(humidity: Double) -> Double {
            var simulation = Fixture.thrivingSimulation()
            simulation.mutateWorld { world in
                world.hive.resources = ResourcePool([.nectar: 200])
                world.hive.bees.removeAll { $0.isBrood }
            }
            simulation.forceWeather(humidity: humidity)

            for _ in 0..<8 {
                _ = simulation.step()
                simulation.forceWeather(humidity: humidity)
            }
            return simulation.hive.resources[.honey]
        }

        XCTAssertGreaterThan(honeyMade(humidity: 0.1), honeyMade(humidity: 0.95))
    }

    // MARK: - Storage limits

    func testWaterDoesNotAccumulateWithoutBound() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather()
        simulation.runDays(20)

        XCTAssertLessThanOrEqual(
            simulation.hive.resources[.water],
            ResourceKind.water.uncappedStorageLimit + 1,
            "water carriers are hoarding an unbounded lake"
        )
    }

    func testResourcePoolRespectsLimits() {
        var pool = ResourcePool()
        let overflow = pool.add(100, of: .water, limit: 40)

        XCTAssertEqual(pool[.water], 40, accuracy: 0.001)
        XCTAssertEqual(overflow, 60, accuracy: 0.001)
    }

    func testResourcePoolNeverGoesNegative() {
        var pool = ResourcePool([.honey: 10])
        let taken = pool.drain(50, of: .honey)

        XCTAssertEqual(taken, 10, accuracy: 0.001)
        XCTAssertEqual(pool[.honey], 0)
    }

    func testAllOrNothingConsumption() {
        var pool = ResourcePool([.wax: 5])
        XCTAssertFalse(pool.consume(10, of: .wax))
        XCTAssertEqual(pool[.wax], 5, accuracy: 0.001, "a failed consume must not part-spend")
        XCTAssertTrue(pool.consume(5, of: .wax))
        XCTAssertEqual(pool[.wax], 0)
    }

    func testStoredResourcesOccupyComb() {
        var pool = ResourcePool()
        pool.add(40, of: .honey)
        XCTAssertEqual(pool.cellsOccupied, 10)

        // Water and propolis live in bees and on walls, not in cells.
        pool.add(100, of: .water)
        XCTAssertEqual(pool.cellsOccupied, 10)
    }

    // MARK: - Spoilage

    func testRoyalJellyPerishes() {
        var simulation = Fixture.barrenSimulation()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.royalJelly: 50])
            world.hive.bees.removeAll()
        }

        simulation.runDays(5)
        XCTAssertLessThan(
            simulation.hive.resources[.royalJelly], 50 * 0.5,
            "royal jelly should perish within days"
        )
    }

    /// Honey does not spoil — that is the entire point of making it.
    func testHoneyDoesNotSpoil() {
        XCTAssertEqual(ResourceKind.honey.dailySpoilage, 0)
        XCTAssertEqual(ResourceKind.wax.dailySpoilage, 0)
        XCTAssertGreaterThan(ResourceKind.royalJelly.dailySpoilage, 0)
    }

    /// An undefended hive full of honey does not keep it. This started life as
    /// a failing "honey keeps forever" test — the stores were vanishing, and
    /// the cause turned out to be robbers and ants helping themselves to an
    /// abandoned nest, which is exactly right.
    func testAbandonedHiveIsRobbed() {
        var simulation = Fixture.barrenSimulation()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool([.honey: 300])
            world.hive.bees.removeAll()
        }

        let report = simulation.runDays(120)

        XCTAssertLessThan(simulation.hive.resources[.honey], 300)
        XCTAssertGreaterThan(report.storesRaided, 0)
        XCTAssertFalse(report.attacks.isEmpty)
    }

    // MARK: - Flight economics

    func testForagingCostsHoney() {
        var near = Fixture.thrivingSimulation(patches: 6, distance: 100, seed: 5)
        var far = Fixture.thrivingSimulation(patches: 6, distance: 6_000, seed: 5)

        near.forceWeather()
        far.forceWeather()

        near.runDays(5)
        far.runDays(5)

        XCTAssertGreaterThan(
            near.hive.resources.edibleEnergy,
            far.hive.resources.edibleEnergy,
            "distance is not costing the colony anything"
        )
    }
}
