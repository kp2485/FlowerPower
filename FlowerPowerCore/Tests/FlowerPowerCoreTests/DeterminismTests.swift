import XCTest
@testable import FlowerPowerCore

/// The engine's two load-bearing guarantees. If either of these breaks, every
/// other behaviour in the game becomes untrustworthy: closing the app would
/// change the outcome, and a save file would resume into a different world.
final class DeterminismTests: XCTestCase {

    func testSameSeedReplaysIdentically() {
        var a = Fixture.thrivingSimulation(seed: 99)
        var b = Fixture.thrivingSimulation(seed: 99)

        a.runDays(30)
        b.runDays(30)

        XCTAssertEqual(a, b, "identical seeds diverged")
    }

    func testDifferentSeedsDiverge() {
        var a = Fixture.thrivingSimulation(seed: 1)
        var b = Fixture.thrivingSimulation(seed: 2)

        a.runDays(30)
        b.runDays(30)

        XCTAssertNotEqual(a, b, "the seed is not actually driving anything")
    }

    /// Offline catch-up must produce exactly the state that live play would.
    func testCatchUpMatchesLivePlay() {
        var live = Fixture.thrivingSimulation(seed: 5)
        var offline = Fixture.thrivingSimulation(seed: 5)

        let days = 21
        live.runDays(days)
        offline.advance(to: .afterSimulated(days: Double(days)))

        XCTAssertEqual(live, offline, "offline catch-up diverged from live play")
    }

    /// Entity ids must come from the seeded generator, never from `UUID()`.
    func testEntityIdentifiersAreDeterministic() {
        var a = Fixture.thrivingSimulation(seed: 3)
        var b = Fixture.thrivingSimulation(seed: 3)

        a.runDays(14)
        b.runDays(14)

        XCTAssertEqual(a.hive.bees.map(\.id), b.hive.bees.map(\.id))
        XCTAssertFalse(a.hive.bees.isEmpty, "no bees were created, so this proved nothing")
    }

    func testEntityIdentifiersAreUnique() {
        var simulation = Fixture.thrivingSimulation(seed: 11)
        simulation.runDays(40)

        let ids = simulation.hive.bees.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate bee identifiers issued")
    }

    // MARK: - Persistence

    func testSimulationRoundTripsThroughCodable() throws {
        var simulation = Fixture.thrivingSimulation(seed: 21)
        simulation.runDays(12)

        let data = try JSONEncoder().encode(simulation)
        let restored = try JSONDecoder().decode(Simulation.self, from: data)

        XCTAssertEqual(simulation, restored)
    }

    /// Saving and reloading mid-game must not change what happens next, or the
    /// random stream has been lost across the save.
    func testRestoredSimulationContinuesIdentically() throws {
        var original = Fixture.thrivingSimulation(seed: 33)
        original.runDays(10)

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(Simulation.self, from: data)

        original.runDays(10)
        restored.runDays(10)

        XCTAssertEqual(original, restored, "the simulation diverged across a save/load")
    }

    /// Ids must not be reissued after a reload.
    func testIdentifierGeneratorSurvivesSaving() throws {
        var original = Fixture.thrivingSimulation(seed: 44)
        original.runDays(25)
        let idsBefore = Set(original.hive.bees.map(\.id))

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(Simulation.self, from: data)
        restored.runDays(25)

        let newIds = restored.hive.bees.map(\.id).filter { !idsBefore.contains($0) }
        XCTAssertEqual(Set(newIds).count, newIds.count)
        XCTAssertFalse(newIds.isEmpty, "no new bees, so this proved nothing")
    }

    // MARK: - Clock

    func testAdvancingBackwardsDoesNothing() {
        var simulation = Fixture.thrivingSimulation()
        let report = simulation.advance(to: epoch.addingTimeInterval(-10_000))
        XCTAssertEqual(report.ticksSimulated, 0)
    }

    /// A long absence must not lock the app in a stepping loop, and the clock
    /// must not stay behind real time afterwards.
    func testCatchUpIsCappedButClockResynchronizes() {
        var simulation = Fixture.thrivingSimulation()
        simulation.clock.maxCatchUpDays = 2

        let farFuture = Date.afterSimulated(days: 400)
        let report = simulation.advance(to: farFuture)

        XCTAssertEqual(report.ticksSimulated, 2 * SimClock.ticksPerDay)
        XCTAssertEqual(simulation.clock.pendingTicks(at: farFuture), 0)
    }

    func testRepeatedCatchUpEqualsOneLongCatchUp() {
        var incremental = Fixture.thrivingSimulation(seed: 77)
        var single = Fixture.thrivingSimulation(seed: 77)

        for day in 1...15 {
            incremental.advance(to: .afterSimulated(days: Double(day)))
        }
        single.advance(to: .afterSimulated(days: 15))

        XCTAssertEqual(incremental, single)
    }

    // MARK: - Pipeline

    func testPipelineIsWiredUp() {
        let names = Simulation.systemNames
        XCTAssertTrue(names.contains("ForagingSystem"))
        XCTAssertTrue(names.contains("QueenSystem"))
        XCTAssertTrue(names.contains("DiseaseSystem"))
        XCTAssertTrue(names.contains("ThermoregulationSystem"))
        // Posture expiry runs before weather; it depends on nothing and the
        // day's stance should be settled before anything reads it.
        XCTAssertEqual(names.first, "PostureSystem")
        XCTAssertLessThan(
            names.firstIndex(of: "WeatherSystem") ?? .max,
            names.firstIndex(of: "ForagingSystem") ?? .min,
            "weather must run before anything depending on it"
        )
        // Status observes the finished state; the lineage system after it
        // only reads the tick's events and changes nothing the status looks at.
        XCTAssertEqual(names.last, "LineageSystem")
        XCTAssertEqual(names.dropLast().last, "ColonyStatusSystem",
                       "status must observe the finished state")
    }
}
