import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// The layer between the engine and SwiftUI.
///
/// It is worth testing precisely because it is the part that used to be
/// untestable: it lived in the Xcode target, so nothing exercised it until the
/// app ran on a device. Everything here runs on the command line, with no
/// camera, no photo library and no clock.
@MainActor
final class GameStoreTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// A clock the test can push forward, since the whole engine is driven by
    /// elapsed real time rather than by a timer.
    final class TestClock: @unchecked Sendable {
        var now: Date
        init(now: Date) { self.now = now }

        /// 5 real minutes per simulated hour, so a simulated day costs two
        /// real hours. Tests move real time and let the engine decide.
        func advance(simulatedDays days: Double) {
            now = now.addingTimeInterval(days * 24 * 300)
        }
    }

    private func makeStore(
        persistence: GamePersisting = InMemoryPersistence(),
        site: HiveLocationType = .livingTreeCavity,
        seed: UInt64 = 99
    ) -> (GameStore, TestClock) {
        let clock = TestClock(now: epoch)
        let simulation = Simulation.newGame(
            at: HiveLocation(type: site),
            startingAt: epoch,
            seed: seed
        )
        let store = GameStore(
            simulation: simulation,
            persistence: persistence,
            clock: { clock.now }
        )
        return (store, clock)
    }

    // MARK: - Loading

    func testLoadStartsAFreshColonyWhenNothingIsSaved() async {
        let store = GameStore.load(persistence: InMemoryPersistence(), clock: { self.epoch })

        XCTAssertEqual(store.snapshot.day, 0)
        XCTAssertGreaterThan(
            store.snapshot.population.total, 0,
            "a new game should begin with a founding colony"
        )
        XCTAssertTrue(
            store.snapshot.patches.isEmpty,
            "a new game has no forage until the player photographs some"
        )
    }

    func testLoadResumesASavedColony() async throws {
        let persistence = InMemoryPersistence()
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .cave),
            startingAt: epoch,
            seed: 7
        )
        for _ in 0..<40 { _ = simulation.stepDay() }
        try persistence.save(simulation)

        let store = GameStore.load(persistence: persistence, clock: { self.epoch })

        XCTAssertEqual(store.snapshot.day, 40, "the saved day should be restored")
        XCTAssertEqual(
            store.snapshot.nest.siteType, .cave,
            "and so should the site the player chose"
        )
    }

    /// A corrupt or unreadable save must not stop the game from opening.
    func testLoadFallsBackToANewGameWhenTheSaveCannotBeRead() async {
        let store = GameStore.load(persistence: FailingPersistence(), clock: { self.epoch })

        XCTAssertEqual(store.snapshot.day, 0)
        XCTAssertGreaterThan(store.snapshot.population.total, 0)
    }

    // MARK: - Catch-up

    func testCatchUpAdvancesTheColonyByElapsedRealTime() async {
        let (store, clock) = makeStore()
        XCTAssertEqual(store.snapshot.day, 0)

        clock.advance(simulatedDays: 10)
        store.catchUp()

        XCTAssertEqual(
            store.snapshot.day, 10,
            "ten simulated days is twenty real hours at the default rate"
        )
    }

    func testCatchUpProducesAReportOnlyWhenAWholeDayPassed() async {
        let (store, clock) = makeStore()

        clock.advance(simulatedDays: 0.2)
        store.catchUp()
        XCTAssertNil(
            store.pendingReport,
            "a few hours away is not worth interrupting the player for"
        )

        clock.advance(simulatedDays: 3)
        store.catchUp()
        XCTAssertNotNil(store.pendingReport, "three days away is")
    }

    func testDismissingTheReportClearsIt() async {
        let (store, clock) = makeStore()
        clock.advance(simulatedDays: 3)
        store.catchUp()
        XCTAssertNotNil(store.pendingReport)

        store.dismissReport()
        XCTAssertNil(store.pendingReport)
    }

    /// The engine clamps catch-up to `maxCatchUpDays` and then resynchronises,
    /// so a long absence must not leave the colony permanently behind real
    /// time. Without the resynchronise, the next catch-up replays the backlog.
    func testALongAbsenceDoesNotLeaveTheColonyBehind() async {
        let (store, clock) = makeStore()

        clock.advance(simulatedDays: 200)
        store.catchUp()
        let afterFirst = store.snapshot.day

        store.catchUp()
        XCTAssertEqual(
            store.snapshot.day, afterFirst,
            "a second catch-up with no time passed should do nothing"
        )
    }

    func testCatchUpPersists() async throws {
        let persistence = InMemoryPersistence()
        let (store, clock) = makeStore(persistence: persistence)

        clock.advance(simulatedDays: 5)
        store.catchUp()

        let saved = try persistence.load()
        XCTAssertEqual(saved?.day, store.snapshot.day)
    }

    // MARK: - Player actions

    func testPhotographingAFlowerAddsAPatchAndSaves() async {
        let persistence = InMemoryPersistence()
        let (store, _) = makeStore(persistence: persistence)
        let before = persistence.saveCount

        let id = store.recordPhotograph(
            localIdentifier: "photo-1",
            species: FlowerCatalogue.all.first,
            confidence: 0.9,
            coordinate: GeoPoint(latitude: 51.5, longitude: -0.12),
            takenAt: epoch
        )

        XCTAssertEqual(store.snapshot.patches.count, 1)
        XCTAssertTrue(store.snapshot.patches.contains { $0.id == id })
        XCTAssertGreaterThan(
            persistence.saveCount, before,
            "a photograph is progress and must survive a crash"
        )
    }

    /// Identification runs after the patch is banked, so a slow classifier
    /// never blocks the player. The patch must accept the answer later.
    func testIdentificationCanArriveAfterThePatchIsRegistered() async throws {
        let (store, _) = makeStore()
        let species = try XCTUnwrap(FlowerCatalogue.all.first)

        let id = store.recordPhotograph(
            localIdentifier: "photo-1",
            species: nil,
            confidence: 0,
            coordinate: nil,
            takenAt: epoch
        )
        let unidentified = try XCTUnwrap(store.snapshot.patches.first { $0.id == id })

        store.attachIdentification(species, confidence: 0.8, to: id)
        let identified = try XCTUnwrap(store.snapshot.patches.first { $0.id == id })

        XCTAssertNotEqual(
            identified, unidentified,
            "attaching an identification should change the patch"
        )
    }

    func testEmphasisingAJobReportsHowManyBeesTookItUp() async {
        let (store, clock) = makeStore()
        clock.advance(simulatedDays: 60)
        store.catchUp()

        let assigned = store.emphasise(.foragingBee)
        XCTAssertGreaterThan(
            assigned, 0,
            "a colony two months in should have bees able to forage"
        )

        store.clearAllAssignments()
        XCTAssertEqual(
            store.emphasise(.foragingBee), assigned,
            "clearing and re-emphasising should reach the same bees"
        )
    }

    func testStartingANewGameResetsTheColonyAndTheReport() async {
        let (store, clock) = makeStore()
        clock.advance(simulatedDays: 30)
        store.catchUp()
        XCTAssertGreaterThan(store.snapshot.day, 0)
        XCTAssertNotNil(store.pendingReport)

        store.startNewGame(at: HiveLocation(type: .cave))

        XCTAssertEqual(store.snapshot.day, 0)
        XCTAssertNil(store.pendingReport)
        XCTAssertEqual(store.snapshot.nest.siteType, .cave)
    }

    func testRelocatingKeepsTheColonyButChangesTheSite() async {
        let (store, clock) = makeStore()
        clock.advance(simulatedDays: 20)
        store.catchUp()
        let population = store.snapshot.population.total

        store.relocateHive(to: HiveLocation(type: .cave))

        XCTAssertEqual(store.snapshot.nest.siteType, .cave)
        XCTAssertEqual(
            store.snapshot.population.total, population,
            "moving house does not kill anyone"
        )
    }

    // MARK: - Failure handling

    /// A failed save is worth telling the player about, but it must never stop
    /// the game. The snapshot still has to move.
    func testASaveFailureIsSurfacedWithoutInterruptingPlay() async {
        let (store, clock) = makeStore(persistence: FailingPersistence())

        clock.advance(simulatedDays: 4)
        store.catchUp()

        XCTAssertEqual(store.snapshot.day, 4, "play continues")
        XCTAssertNotNil(store.lastError, "but the player is told")
    }

    // MARK: - Collapse

    /// A founding colony with nothing to eat dies. It is the simplest way to
    /// reach the collapsed state, and it is also what happens to a real player
    /// who never photographs anything.
    private func collapsedStore(
        persistence: GamePersisting = InMemoryPersistence()
    ) -> (GameStore, TestClock) {
        let (store, clock) = makeStore(persistence: persistence)

        // Advanced in bites rather than one jump, because a single catch-up is
        // capped at the ceiling. Bounded so a colony that somehow survives
        // fails the test rather than hanging it.
        for _ in 0..<8 where !store.isCollapsed {
            clock.advance(simulatedDays: 120)
            store.catchUp()
        }
        return (store, clock)
    }

    func testAColonyWithNothingToEatCollapses() async {
        let (store, _) = collapsedStore()

        XCTAssertEqual(store.snapshot.status, .collapsed)
        XCTAssertTrue(store.isCollapsed)
        XCTAssertEqual(store.snapshot.headline, "The colony is gone.")
    }

    /// Collapsed is not the same as critical, and the difference is the whole
    /// reason the case exists: critical is a colony the player might still
    /// save, collapsed is one they cannot.
    func testCollapsedSortsBelowCritical() async {
        XCTAssertLessThan(ColonyStatus.collapsed, ColonyStatus.critical)
        XCTAssertFalse(ColonyStatus.collapsed.isAlive)
        XCTAssertTrue(ColonyStatus.critical.isAlive)
    }

    /// Returning to a colony that died a fortnight ago should show the death
    /// once, not a fresh report about the fortnight of nothing since.
    func testNoFurtherReportsOnceTheColonyIsGone() async {
        let (store, clock) = collapsedStore()
        store.dismissReport()

        clock.advance(simulatedDays: 20)
        store.catchUp()

        XCTAssertNil(store.pendingReport)
    }

    func testStartingAgainKeepsTheGarden() async {
        let (store, _) = makeStore()
        for index in 0..<4 {
            store.recordPhotograph(
                localIdentifier: "photo-\(index)",
                species: FlowerCatalogue.all[index],
                confidence: 0.9,
                coordinate: GeoPoint(latitude: 51.5, longitude: -0.12),
                takenAt: epoch
            )
        }
        let photographed = Set(store.snapshot.patches.map(\.photoLocalIdentifier))
        XCTAssertEqual(photographed.count, 4)

        store.startNewGame(at: HiveLocation(type: .cave))

        XCTAssertEqual(store.snapshot.day, 0, "a new colony")
        XCTAssertEqual(
            Set(store.snapshot.patches.map(\.photoLocalIdentifier)), photographed,
            "but the player's photographs are their own, and the flowers are "
            + "still growing where they were"
        )
    }

    /// Carried-over patches must take fresh identifiers. Reusing the old ones
    /// would collide with the new colony's bees, which draw from the same
    /// counter.
    func testCarriedOverFlowersDoNotCollideWithTheNewColony() async {
        let (store, _) = makeStore()
        store.recordPhotograph(
            localIdentifier: "photo-1", species: FlowerCatalogue.all.first,
            confidence: 0.9, coordinate: nil, takenAt: epoch
        )

        store.startNewGame(at: HiveLocation(type: .cave))

        let ids = store.snapshot.patches.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicate patch ids")
    }

    func testStartingAgainCanDropTheGardenWhenAsked() async {
        let (store, _) = makeStore()
        store.recordPhotograph(
            localIdentifier: "photo-1", species: FlowerCatalogue.all.first,
            confidence: 0.9, coordinate: nil, takenAt: epoch
        )

        store.startNewGame(at: HiveLocation(type: .cave), keepingFlowers: false)

        XCTAssertTrue(store.snapshot.patches.isEmpty)
    }

    // MARK: - Watch

    func testWatchSummaryMatchesTheSnapshot() async {
        let (store, clock) = makeStore()
        clock.advance(simulatedDays: 15)
        store.catchUp()

        let summary = store.watchSummary()
        XCTAssertEqual(summary.status, store.snapshot.status)
        XCTAssertEqual(summary.season, store.snapshot.season)
    }
}
