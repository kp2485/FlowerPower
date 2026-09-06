import XCTest
@testable import FlowerPowerCore

/// The photo loop. These are the tests that protect the game's core promise:
/// what you photograph is what your bees eat.
final class ForagingTests: XCTestCase {

    // MARK: - The camera is the only tap

    func testNoPatchesMeansNoForage() {
        var simulation = Fixture.barrenSimulation()
        let nectarBefore = simulation.hive.resources[.nectar]

        simulation.runDays(3)

        XCTAssertLessThanOrEqual(
            simulation.hive.resources[.nectar], nectarBefore,
            "nectar appeared without a single photographed flower"
        )
        XCTAssertEqual(simulation.totalRemainingNectar, 0)
    }

    func testPhotographedFlowersFeedTheHive() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather()

        let before = simulation.totalRemainingNectar
        simulation.runDays(2)

        XCTAssertLessThan(simulation.totalRemainingNectar, before, "no nectar was taken from the patches")
        XCTAssertGreaterThan(simulation.hive.resources.edibleEnergy, 0)
    }

    // MARK: - Identification

    /// A photo the classifier could not place must still be playable, only less
    /// rewarding — otherwise a bad photo breaks the core loop.
    func testUnidentifiedFlowerStillYieldsForage() {
        let unknown = FlowerPatch(
            id: EntityID(rawValue: 1),
            photoLocalIdentifier: "blurry",
            species: nil,
            discoveredAt: epoch
        )

        XCTAssertGreaterThan(unknown.remainingNectar, 0)
        XCTAssertGreaterThan(unknown.remainingPollen, 0)
        XCTAssertEqual(unknown.resolvedSpecies.id, FlowerSpecies.unidentified.id)
        XCTAssertFalse(unknown.isIdentified)
    }

    func testConfidentIdentificationYieldsMore() {
        func capacity(confidence: Double) -> Double {
            FlowerPatch(
                id: EntityID(rawValue: 1),
                photoLocalIdentifier: "x",
                species: Fixture.clover,
                identificationConfidence: confidence,
                discoveredAt: epoch
            ).nectarCapacity
        }
        XCTAssertGreaterThan(capacity(confidence: 1.0), capacity(confidence: 0.0))
    }

    func testRarerFlowersYieldMore() {
        func capacity(_ rarity: FlowerRarity) -> Double {
            FlowerPatch(
                id: EntityID(rawValue: 1),
                photoLocalIdentifier: "x",
                species: FlowerSpecies(
                    id: "f", commonName: "F",
                    taxon: Taxon(family: .rosaceae), rarity: rarity
                ),
                discoveredAt: epoch
            ).nectarCapacity
        }
        XCTAssertGreaterThan(capacity(.rare), capacity(.uncommon))
        XCTAssertGreaterThan(capacity(.uncommon), capacity(.common))
    }

    /// Classification often finishes after the photo is registered.
    func testLateIdentificationUpgradesThePatch() {
        var simulation = Fixture.barrenSimulation()
        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: "late",
            species: nil,
            confidence: 0,
            coordinate: nil,
            takenAt: epoch
        )
        let before = patch.nectarCapacity

        simulation.identifyPatch(patch.id, as: Fixture.heather, confidence: 0.95)

        let after = simulation.patches[0]
        XCTAssertTrue(after.isIdentified)
        XCTAssertGreaterThan(after.nectarCapacity, before)
        XCTAssertEqual(after.id, patch.id, "identification must not reissue the patch id")
    }

    // MARK: - Distance

    func testDistantPatchesReturnLess() {
        let near = FlowerPatch(
            id: EntityID(rawValue: 1), photoLocalIdentifier: "near",
            species: Fixture.clover, distanceMetres: 100, discoveredAt: epoch
        )
        let far = FlowerPatch(
            id: EntityID(rawValue: 2), photoLocalIdentifier: "far",
            species: Fixture.clover, distanceMetres: 4_000, discoveredAt: epoch
        )

        XCTAssertGreaterThan(near.distanceEfficiency, far.distanceEfficiency)
        XCTAssertGreaterThan(
            near.forageQuality(onDay: 0, config: .standard),
            far.forageQuality(onDay: 0, config: .standard)
        )
    }

    func testPatchesBeyondForagingRangeAreUseless() {
        let outOfRange = FlowerPatch(
            id: EntityID(rawValue: 1), photoLocalIdentifier: "distant",
            species: Fixture.clover,
            distanceMetres: FlowerPatch.maximumForagingRange + 1,
            discoveredAt: epoch
        )

        XCTAssertFalse(outOfRange.isWithinRange)
        XCTAssertEqual(outOfRange.distanceEfficiency, 0)
        XCTAssertEqual(outOfRange.forageQuality(onDay: 0, config: .standard), 0)
    }

    func testHiveRelocationRecomputesPatchDistances() {
        var simulation = Simulation.newGame(
            at: HiveLocation(coordinate: GeoPoint(latitude: 51.50, longitude: -0.12), type: .nestbox),
            startingAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "p",
            species: Fixture.clover,
            confidence: 1,
            coordinate: GeoPoint(latitude: 51.51, longitude: -0.12),
            takenAt: epoch
        )
        let originalDistance = simulation.patches[0].distanceMetres
        XCTAssertGreaterThan(originalDistance, 500)

        // Move the hive right next to the flowers.
        simulation.relocate(to: HiveLocation(
            coordinate: GeoPoint(latitude: 51.51, longitude: -0.12),
            type: .nestbox
        ))

        XCTAssertLessThan(simulation.patches[0].distanceMetres, 50)
    }

    func testGeoDistanceIsRoughlyCorrect() {
        // One degree of latitude is about 111 km.
        let a = GeoPoint(latitude: 0, longitude: 0)
        let b = GeoPoint(latitude: 1, longitude: 0)
        XCTAssertEqual(a.distance(to: b), 111_195, accuracy: 500)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 0.001)
    }

    // MARK: - The waggle dance

    /// Recruitment must concentrate the workforce on the best forage rather
    /// than spreading it evenly — that concentration is the whole point of the
    /// dance, and it is what makes photographing a good flower worthwhile.
    /// Two identical flowers, one close and one far. Recruitment is superlinear
    /// in patch quality, so the colony should not split its effort evenly — it
    /// should pile onto the near one.
    func testForagersConcentrateOnTheBestPatch() {
        var simulation = Fixture.barrenSimulation()

        simulation.registerPhotograph(
            photoLocalIdentifier: "near", species: Fixture.clover,
            confidence: 1.0, coordinate: nil, takenAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "far", species: Fixture.clover,
            confidence: 1.0, coordinate: nil, takenAt: epoch
        )
        simulation.setDistance(150, forPatchAt: 0)
        simulation.setDistance(5_000, forPatchAt: 1)

        simulation.mutateWorld { world in
            // Room to store what they bring back: a honey-bound colony cannot
            // accept nectar at all, and the test would measure nothing.
            world.hive.comb = Comb(workerCells: 300, droneCells: 40, capacity: 700)
            world.hive.resources.add(60, of: .honey)
            // A real foraging force, so the split is measurable.
            for index in 0..<40 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(300_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 25
                ))
            }
        }

        let nearBefore = simulation.patches[0].remainingNectar
        let farBefore = simulation.patches[1].remainingNectar

        for _ in 0..<(3 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather(sky: .clear, temperature: 22)
        }

        let nearTaken = nearBefore - simulation.patches[0].remainingNectar
        let farTaken = farBefore - simulation.patches[1].remainingNectar

        XCTAssertGreaterThan(nearTaken, 0, "nothing was foraged at all")
        XCTAssertGreaterThan(nearTaken, farTaken * 2, "the dance is not concentrating effort")
    }

    /// A rarer, richer flower should out-compete a plain one at equal distance.
    func testRicherFlowersAttractMoreForagers() {
        var simulation = Fixture.barrenSimulation()

        // Heather blooms in autumn; clover blooms then too, so both are live.
        // The clock moves *before* the photographs are registered, because a
        // patch fades from the day it was photographed — registering on day 0
        // and then time-travelling to day 200 lands both patches well past the
        // end of their stand, and two flowers that are equally gone are
        // equally uninteresting to a scout.
        simulation.clock = SimClock(epoch: epoch, tick: 200 * SimClock.ticksPerDay)

        simulation.registerPhotograph(
            photoLocalIdentifier: "rich", species: Fixture.heather,
            confidence: 1.0, coordinate: nil, takenAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "plain", species: Fixture.clover,
            confidence: 1.0, coordinate: nil, takenAt: epoch
        )
        simulation.setDistance(400, forPatchAt: 0)
        simulation.setDistance(400, forPatchAt: 1)
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 300, droneCells: 40, capacity: 700)
            world.hive.resources.add(60, of: .honey)
            for index in 0..<40 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(310_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 25
                ))
            }
        }

        XCTAssertGreaterThan(
            simulation.patches[0].forageQuality(onDay: simulation.day, config: .standard),
            simulation.patches[1].forageQuality(onDay: simulation.day, config: .standard),
            "a rare keystone flower is not rated above plain clover"
        )

        for _ in 0..<(3 * SimClock.ticksPerDay) {
            _ = simulation.step()
            simulation.forceWeather(sky: .clear, temperature: 22)
        }

        XCTAssertGreaterThan(simulation.patches[0].recruitedForagers, 0)
    }

    // MARK: - Bloom

    func testOutOfSeasonFlowersYieldNothing() {
        var simulation = Fixture.barrenSimulation()
        simulation.registerPhotograph(
            photoLocalIdentifier: "crocus", species: Fixture.crocus,
            confidence: 1, coordinate: nil, takenAt: epoch
        )
        simulation.setDistance(200, forPatchAt: 0)

        // Jump to summer, when crocus is long over.
        simulation.clock = SimClock(epoch: epoch, tick: 120 * SimClock.ticksPerDay)
        simulation.forceWeather()

        let before = simulation.patches[0].remainingNectar
        simulation.runDays(3)

        XCTAssertEqual(simulation.patches[0].remainingNectar, before, accuracy: 0.001)
        XCTAssertFalse(simulation.patches[0].isInBloom(during: .summer))
        XCTAssertTrue(simulation.patches[0].isInBloom(during: .spring))
    }

    func testPatchesRegrowWhileInBloom() {
        var patch = FlowerPatch(
            id: EntityID(rawValue: 1), photoLocalIdentifier: "p",
            species: Fixture.clover, discoveredAt: epoch
        )
        _ = patch.harvest(nectar: patch.remainingNectar, pollen: patch.remainingPollen)
        XCTAssertTrue(patch.isDepleted)

        patch.regrow(rate: 0.2, onDay: 0, config: .standard)
        XCTAssertFalse(patch.isDepleted)
        XCTAssertLessThanOrEqual(patch.remainingNectar, patch.nectarCapacity)
    }

    func testRegrowthNeverExceedsCapacity() {
        var patch = FlowerPatch(
            id: EntityID(rawValue: 1), photoLocalIdentifier: "p",
            species: Fixture.clover, discoveredAt: epoch
        )
        for _ in 0..<50 { patch.regrow(rate: 0.5, onDay: 0, config: .standard) }
        XCTAssertEqual(patch.remainingNectar, patch.nectarCapacity, accuracy: 0.001)
    }

    // MARK: - Time of day and weather

    func testForagersRestAtNight() {
        var simulation = Fixture.thrivingSimulation()
        simulation.forceWeather()

        simulation.runUntilHour(21)
        simulation.forceWeather()
        let before = simulation.totalRemainingNectar

        _ = simulation.step()
        XCTAssertEqual(simulation.totalRemainingNectar, before, accuracy: 0.0001)
    }

    func testForagersWorkByDay() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runUntilHour(11)
        simulation.forceWeather()
        let before = simulation.totalRemainingNectar

        _ = simulation.step()
        XCTAssertLessThan(simulation.totalRemainingNectar, before)
    }

    func testStormGroundsTheColony() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runUntilHour(11)
        simulation.forceWeather(sky: .storm, temperature: 20, wind: 14)

        let before = simulation.totalRemainingNectar
        _ = simulation.step()

        XCTAssertEqual(simulation.totalRemainingNectar, before, accuracy: 0.0001)
    }

    func testColdGroundsTheColony() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runUntilHour(11)
        simulation.forceWeather(sky: .clear, temperature: 5)

        let before = simulation.totalRemainingNectar
        _ = simulation.step()

        XCTAssertEqual(simulation.totalRemainingNectar, before, accuracy: 0.0001)
        XCTAssertFalse(simulation.weather.isFlyingWeather)
    }
}
