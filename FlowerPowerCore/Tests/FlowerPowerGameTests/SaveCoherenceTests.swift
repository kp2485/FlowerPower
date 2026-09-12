import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

/// The save file has more than one writer.
///
/// `GameStore` keeps the colony in memory and writes it over the file on every
/// catch-up. A tapped notification action, a widget button and a Shortcut all
/// act on the file directly, because they can arrive with no interface running
/// at all. So the store's twenty-second tick used to overwrite a decision the
/// player had just made on their lock screen, silently, and the only sign was
/// a colony that had not done what it was told.
///
/// What is being tested is therefore an interleaving rather than a function:
/// two stores over one save, one of them stale, and the rule that the stale one
/// notices before it writes. The second store here is built exactly the way
/// `NotificationActions.handle` builds one — around the file, around the same
/// persistence — so what these tests exercise is the real path.
@Suite("Save coherence")
@MainActor
struct SaveCoherenceTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    /// A colony with a swarm gathering, which is the decision that lives in a
    /// notification's action buttons for a week at a time.
    private func gathering(seed: UInt64 = 21) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: seed
        )
        simulation.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        return simulation
    }

    /// The store the interface holds: it came out of the save, so it has a
    /// claim on the file and something to compare against.
    private func appStore(over persistence: GamePersisting) -> GameStore {
        GameStore.load(persistence: persistence, clock: { self.epoch })
    }

    /// The store a notification action builds: around a simulation already in
    /// hand, thrown away immediately afterwards.
    private func lockScreenStore(
        _ simulation: Simulation,
        over persistence: GamePersisting
    ) -> GameStore {
        GameStore(simulation: simulation, persistence: persistence, clock: { self.epoch })
    }

    /// The colony as the save has it. Bound before it is unwrapped because
    /// `#require` wraps what it is given in a closure of its own, which a
    /// throwing call cannot be written inside.
    private func stored(in persistence: GamePersisting) throws -> Simulation {
        let loaded = try persistence.load()
        return try #require(loaded)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flowerpower-coherence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    // MARK: - A decision written from outside

    /// The bug, in one test. The clock does not move, so the only thing that
    /// can put the decision into the app's colony is the reload.
    @Test("A decision answered from the lock screen survives the next catch-up")
    func outsideDecisionSurvives() throws {
        let persistence = InMemoryPersistence()
        try persistence.save(gathering())

        let app = appStore(over: persistence)
        #expect(app.snapshot.pendingSwarm?.discouraged == false)

        let lockScreen = lockScreenStore(try stored(in: persistence), over: persistence)
        #expect(lockScreen.apply(.discourageSwarm))

        app.catchUp()

        #expect(
            app.snapshot.pendingSwarm?.discouraged == true,
            "the store must take in the answer rather than write over it"
        )
        let onDisk = try stored(in: persistence)
        #expect(onDisk.world.pendingSwarm?.discouraged == true)
    }

    /// Not only decisions. Anything another process wrote is in the colony the
    /// store goes on to advance, because the whole simulation is reloaded
    /// rather than some subset of it that somebody has to remember to extend.
    @Test("A name given to the queen from outside survives too")
    func outsideNameSurvives() throws {
        let persistence = InMemoryPersistence()
        try persistence.save(gathering())

        let app = appStore(over: persistence)
        let number = try #require(app.snapshot.lineage.queens.first?.number)

        let outside = lockScreenStore(try stored(in: persistence), over: persistence)
        outside.nameQueen(number, "Boudicca")

        app.catchUp()

        #expect(app.snapshot.lineage.queens.first?.name == "Boudicca")
    }

    /// A report is not the point of a reload, and must not be invented by one.
    /// The colony that arrives was already advanced to the moment the other
    /// process saw; the hours it simulated are gone either way, and handing the
    /// player a sheet about them would be handing them a sheet the events for
    /// which nobody kept.
    @Test("A reload does not manufacture a catch-up report")
    func reloadReportsNothing() throws {
        let persistence = InMemoryPersistence()
        try persistence.save(gathering())

        let app = appStore(over: persistence)
        let lockScreen = lockScreenStore(try stored(in: persistence), over: persistence)
        #expect(lockScreen.apply(.discourageSwarm))

        app.catchUp()

        #expect(app.pendingReport == nil)
    }

    /// And does not clear one either. Those events happened and the player has
    /// not been shown them; a widget button is no reason to take the sheet away.
    @Test("A reload leaves a report the player has not read yet alone")
    func reloadKeepsAWaitingReport() throws {
        let persistence = InMemoryPersistence()
        try persistence.save(gathering())

        // A fortnight of real time, so the first catch-up has something to say.
        let clock = MovableClock(now: epoch)
        let app = GameStore.load(persistence: persistence, clock: { clock.now })
        clock.advance(simulatedDays: 14)
        app.catchUp()
        let report = try #require(app.pendingReport)

        let lockScreen = GameStore(
            simulation: try stored(in: persistence),
            persistence: persistence,
            clock: { clock.now }
        )
        #expect(lockScreen.apply(.discourageSwarm))

        app.catchUp()

        #expect(app.pendingReport == report, "the unread report must still be there")
    }

    // MARK: - When nothing wrote

    /// The reload has to be free when it is not needed: `catchUp` runs every
    /// twenty seconds while the app is in front, and a store that decoded the
    /// whole save on every tick would be a much worse bug than the one being
    /// fixed.
    @Test("A catch-up with no outside write does not go back to the save")
    func noOutsideWriteMeansNoReload() throws {
        let persistence = InMemoryPersistence()
        try persistence.save(gathering())

        let clock = MovableClock(now: epoch)
        let app = GameStore.load(persistence: persistence, clock: { clock.now })
        let loadsAfterLoading = persistence.loadCount

        clock.advance(simulatedDays: 3)
        app.catchUp()
        clock.advance(simulatedDays: 3)
        app.catchUp()

        #expect(
            persistence.loadCount == loadsAfterLoading,
            "the store wrote both of those saves itself and has nothing to re-read"
        )
    }

    /// The throwaway stores the three outside writers build have just read the
    /// file themselves, and reloading it underneath them would at best be
    /// wasted work and at worst — with a fourth writer in between — discard
    /// the answer they were built to apply.
    @Test("A store that has never written the save does not reload one")
    func aStoreWithNoClaimDoesNotReload() throws {
        let persistence = InMemoryPersistence()
        let lockScreen = lockScreenStore(gathering(seed: 1), over: persistence)

        // Somebody else's colony, in the file, while this store holds its own.
        try persistence.save(gathering(seed: 2))
        let loadsBefore = persistence.loadCount

        lockScreen.catchUp()

        #expect(persistence.loadCount == loadsBefore)
    }

    /// And the first run in particular. The colony a store in setup holds is a
    /// placeholder at a site nobody chose, and the file — if a previous colony
    /// left one — is what the player is about to replace. Neither is a reason
    /// to swap one for the other behind the introduction.
    @Test("A store still in setup does not adopt the colony in the file")
    func setupDoesNotReload() throws {
        let persistence = InMemoryPersistence()
        let app = appStore(over: persistence)
        #expect(app.needsSetup)

        var elsewhere = Simulation.newGame(
            at: HiveLocation(type: .cave), startingAt: epoch, seed: 9
        )
        for _ in 0..<30 { _ = elsewhere.stepDay() }
        try persistence.save(elsewhere)

        app.catchUp()

        #expect(app.snapshot.nest.siteType == .livingTreeCavity)
        #expect(app.snapshot.day == 0, "the placeholder colony, not the saved one")
    }

    // MARK: - The token over a real file

    @Test("A file with nothing in it has no token")
    func noFileNoToken() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let token = try GamePersistence(directory: directory).changeToken()
        #expect(token == nil)
    }

    /// Both halves of what the store relies on: the token does not move on its
    /// own, and it does move when somebody else writes.
    @Test("A second writer changes the token; reading it does not")
    func tokenTracksTheFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let mine = GamePersistence(directory: directory)
        var colony = gathering()
        try mine.save(colony)

        let written = try mine.changeToken()
        let afterMySave = try #require(written)

        let readAgain = try mine.changeToken()
        #expect(readAgain == afterMySave, "nothing was written in between")

        // A month on, so the save is a different length as well as a different
        // age — the two halves of the token, and a deliberate choice of
        // fixture: a filesystem's timestamp resolution is coarser than the gap
        // between two saves made in the same test.
        for _ in 0..<30 { _ = colony.stepDay() }
        try GamePersistence(directory: directory).save(colony)

        let afterTheirSave = try mine.changeToken()
        #expect(afterTheirSave != afterMySave)
    }

    /// End to end over a real file, which is the arrangement the bug was
    /// actually reported from: the app in the foreground, an answer tapped on
    /// the lock screen, the store's next tick.
    @Test("An outside decision survives over a real save file")
    func outsideDecisionSurvivesOnDisk() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = GamePersistence(directory: directory)
        try persistence.save(gathering())

        let app = appStore(over: persistence)
        let lockScreen = lockScreenStore(try stored(in: persistence), over: persistence)
        #expect(lockScreen.apply(.discourageSwarm))

        app.catchUp()

        #expect(app.snapshot.pendingSwarm?.discouraged == true)
        let onDisk = try stored(in: persistence)
        #expect(onDisk.world.pendingSwarm?.discouraged == true)
    }

    // MARK: - Failure

    /// A persistence that stops being able to answer must not cost the player
    /// the colony in memory. The store keeps what it has, goes on playing, and
    /// says so — and the saying matters here rather than being a nicety,
    /// because the write it is about to make is over a file it could not read.
    @Test("A save that cannot be checked keeps the colony in memory, and says so")
    func anUnreadableSaveChangesNothing() throws {
        let persistence = UnreliablePersistence()
        try persistence.save(gathering())

        let app = appStore(over: persistence)
        let day = app.snapshot.day

        persistence.refusesToAnswer = true
        app.catchUp()

        #expect(app.snapshot.day == day, "the colony in memory is the one to keep")
        #expect(app.lastError != nil, "and the player is told the save was written blind")
    }

    /// The store's own failure double answers nothing, like everything else on
    /// it — which is what makes it the right thing to test that path with.
    @Test("The failing double refuses to answer")
    func failingPersistenceThrows() {
        #expect(throws: (any Error).self) { try FailingPersistence().changeToken() }
    }
}

/// Saves and loads, and can be told to stop saying whether the save is
/// current — which `FailingPersistence` cannot express, because a store over
/// something that fails every call never gets a token to compare in the first
/// place.
private final class UnreliablePersistence: GamePersisting, @unchecked Sendable {

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "the container went away" }
    }

    private let backing = InMemoryPersistence()
    var refusesToAnswer = false

    func save(_ simulation: Simulation) throws { try backing.save(simulation) }
    func load() throws -> Simulation? { try backing.load() }
    func clear() throws { try backing.clear() }

    func changeToken() throws -> String? {
        if refusesToAnswer { throw Failure() }
        return try backing.changeToken()
    }
}

/// A clock a test can push forward. Five real minutes per simulated hour, as
/// the engine's own tests use it, so moving real time is what advances days.
private final class MovableClock: @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }

    func advance(simulatedDays days: Double) {
        now = now.addingTimeInterval(days * 24 * 300)
    }
}

