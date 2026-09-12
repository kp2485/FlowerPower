import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// Backing the colony up, and putting one back.
///
/// The load-bearing claim is the same one `GamePersistenceTests` makes about
/// the save file — a colony round-trips *exactly* — plus two that only matter
/// because this file leaves the device: a backup from a later build is refused
/// with a sentence, and a restore genuinely replaces what was there and
/// persists it. A restore that only changed the screen would look right and
/// lose the colony on the next launch.
@Suite("The save archive")
struct SaveArchiveTests {

    /// A whole second, deliberately. The encoder is ISO-8601, which carries no
    /// sub-second field, so a colony started at a fractional instant would not
    /// equal itself after a round trip — and that would be a property of the
    /// test's fixture rather than of the archive.
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSimulation(days: Int = 40, seed: UInt64 = 9_191) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(
                coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                type: .livingTreeCavity
            ),
            startingAt: epoch,
            seed: seed
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "clover",
            species: FlowerCatalogue.whiteClover,
            confidence: 0.9,
            coordinate: GeoPoint(latitude: 51.5080, longitude: -0.1280),
            takenAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "borage",
            species: FlowerCatalogue.borage,
            confidence: 0.7,
            coordinate: nil,
            takenAt: epoch
        )
        for _ in 0..<days { _ = simulation.stepDay() }
        return simulation
    }

    @MainActor
    private func makeStore(
        _ simulation: Simulation,
        persistence: GamePersisting
    ) -> GameStore {
        GameStore(simulation: simulation, persistence: persistence, clock: { self.epoch })
    }

    // MARK: - Round trip

    @Test("A backup comes back as the colony that went in")
    func roundTrip() throws {
        let archive = SaveArchive(exportedAt: epoch, simulation: makeSimulation())
        let restored = try SaveArchive.decoded(from: archive.encode())

        #expect(restored == archive)
        #expect(restored.simulation == archive.simulation)
        #expect(restored.formatVersion == SaveArchive.currentFormatVersion)
        #expect(restored.exportedAt == epoch)
    }

    @Test("A colony restored from a backup goes on to behave identically")
    func resumesWithoutDrift() throws {
        var original = makeSimulation()
        var copy = try SaveArchive.decoded(
            from: SaveArchive(exportedAt: epoch, simulation: original).encode()
        ).simulation

        for _ in 0..<20 {
            _ = original.stepDay()
            _ = copy.stepDay()
        }

        #expect(copy == original)
    }

    @Test("An export timestamp is whole seconds, so an archive equals itself")
    func timestampIsWholeSeconds() throws {
        let fractional = Date(timeIntervalSince1970: 1_700_000_000.75)
        let archive = SaveArchive(exportedAt: fractional, simulation: makeSimulation(days: 2))

        #expect(archive.exportedAt == epoch)
        #expect(try SaveArchive.decoded(from: archive.encode()) == archive)
    }

    @Test("The summary says what is in the file")
    func summary() {
        let simulation = makeSimulation()
        let archive = SaveArchive(exportedAt: epoch, simulation: simulation)
        let summary = archive.summary

        #expect(summary.day == simulation.snapshot().day)
        #expect(summary.flowerCount == 2)
        #expect(summary.beeCount > 0)
        #expect(summary.season == simulation.snapshot().season)
        #expect(summary.generation == 1)
    }

    @Test("The suggested filename is dated and carries the extension")
    func fileName() {
        let archive = SaveArchive(exportedAt: epoch, simulation: makeSimulation(days: 1))
        #expect(archive.suggestedFileName.hasSuffix(".flowerhive"))
        #expect(archive.suggestedFileName.contains("2023-11"))
    }

    // MARK: - Refusing what it cannot read

    @Test("A backup from a newer version is refused by version, not by decode")
    func fromTheFuture() throws {
        let archive = SaveArchive(
            formatVersion: SaveArchive.currentFormatVersion + 1,
            exportedAt: epoch,
            simulation: makeSimulation(days: 3)
        )
        let data = try archive.encode()

        #expect(throws: SaveArchive.Failure.fromANewerVersion(
            SaveArchive.currentFormatVersion + 1
        )) {
            _ = try SaveArchive.decoded(from: data)
        }
    }

    /// A future build may also change the *shape* of the file. The version has
    /// to be recognised in that case too, or a player on an old build is told
    /// their backup is corrupt when it is merely newer.
    @Test("A newer backup whose shape also changed still reports its version")
    func fromTheFutureWithADifferentShape() throws {
        let data = Data(#"{"formatVersion":99,"whatever":{"bees":[]}}"#.utf8)

        #expect(throws: SaveArchive.Failure.fromANewerVersion(99)) {
            _ = try SaveArchive.decoded(from: data)
        }
    }

    @Test("Garbage is refused")
    func garbage() {
        #expect(throws: SaveArchive.Failure.notASaveFile) {
            _ = try SaveArchive.decoded(from: Data(repeating: 0x2A, count: 512))
        }
    }

    @Test("Well-formed JSON that is not a colony is refused")
    func notAColony() {
        let data = Data(#"{"formatVersion":1,"id":"x","exportedAt":"2023-11-14T22:13:20Z"}"#.utf8)

        #expect(throws: SaveArchive.Failure.notASaveFile) {
            _ = try SaveArchive.decoded(from: data)
        }
    }

    @Test("A file past the size cap is refused before it is decoded")
    func tooLarge() {
        let data = Data(repeating: 0x7B, count: SaveArchive.maximumBytes + 1)

        #expect(throws: SaveArchive.Failure.tooLarge(data.count)) {
            _ = try SaveArchive.decoded(from: data)
        }
    }

    // MARK: - Through the store

    @Test("The store exports a backup of the colony it is holding")
    @MainActor
    func exportFromStore() throws {
        let simulation = makeSimulation()
        let store = makeStore(simulation, persistence: InMemoryPersistence())

        let archive = try SaveArchive.decoded(from: store.exportArchive())

        #expect(archive.simulation == simulation)
        #expect(archive.formatVersion == SaveArchive.currentFormatVersion)
    }

    @Test("Restoring replaces the colony and writes it to disk")
    @MainActor
    func restoreReplacesAndPersists() throws {
        let persistence = InMemoryPersistence()
        let store = makeStore(makeSimulation(seed: 1), persistence: persistence)
        let saved = persistence.saveCount

        let incoming = makeSimulation(days: 120, seed: 2)
        let before = store.snapshot.day
        store.restore(from: SaveArchive(exportedAt: epoch, simulation: incoming))

        #expect(store.snapshot.day != before)
        #expect(store.snapshot.day == incoming.snapshot().day)
        #expect(persistence.saveCount > saved)
        #expect(try persistence.load() == incoming)

        store.stopLiveUpdates()
    }

    @Test("Restoring clears a report the player had not read yet")
    @MainActor
    func restoreClearsPendingReport() throws {
        let persistence = InMemoryPersistence()
        let store = GameStore(
            simulation: makeSimulation(days: 5),
            persistence: persistence,
            // A clock well ahead of the colony, so catching up produces a
            // report the way returning after a month away does.
            clock: { self.epoch.addingTimeInterval(60 * 60 * 24 * 40) }
        )
        store.catchUp()
        #expect(store.pendingReport != nil)

        store.restore(from: SaveArchive(exportedAt: epoch, simulation: makeSimulation(days: 9)))

        #expect(store.pendingReport == nil)

        store.stopLiveUpdates()
    }
}
