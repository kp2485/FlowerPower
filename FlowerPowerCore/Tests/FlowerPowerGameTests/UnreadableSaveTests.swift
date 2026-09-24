import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

/// A save that is there and cannot be read is not the same as no save.
///
/// `GameStore.load` used to treat the two alike: it started a fresh colony,
/// and the moment the player chose a site that colony was written over the
/// file it could not read. So any decode failure — a key added since the save
/// was written, a value from a later build — deleted somebody's colony without
/// a word. `SaveCompatibilityTests` is what stops the first of those happening;
/// this is what makes the second survivable, and every other one.
@Suite("An unreadable save")
@MainActor
struct UnreadableSaveTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func colony(days: Int = 3) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .cave),
            startingAt: epoch,
            seed: 4_242
        )
        for _ in 0..<days { _ = simulation.stepDay() }
        return simulation
    }

    /// A save as a later build might write it: a posture this build has
    /// never heard of, which no default can stand in for.
    private func saveFromALaterBuild() throws -> Data {
        let data = try GamePersistence.encodeForTransfer(colony())
        var document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var world = try #require(document["world"] as? [String: Any])
        world["posture"] = "somethingNewer"
        document["world"] = world
        return try JSONSerialization.data(withJSONObject: document)
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UnreadableSaveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    // MARK: - Kept

    @Test("A save that will not decode is kept beside the new colony, byte for byte")
    func unreadableSaveIsKept() throws {
        try withDirectory { directory in
            let persistence = GamePersistence(directory: directory)
            let unreadable = try saveFromALaterBuild()
            try unreadable.write(to: persistence.saveURL)
            #expect(throws: (any Error).self) { try persistence.load() }

            let store = GameStore.load(persistence: persistence, clock: { self.epoch })

            #expect(store.needsSetup, "the player is offered a new colony")
            #expect(store.lastError == GameStore.setAsideMessage, "and told why")
            let kept = directory.appendingPathComponent(GamePersistence.unreadableFileName)
            #expect(try Data(contentsOf: kept) == unreadable)

            // Choosing a site is what used to write over it.
            store.startNewGame(at: HiveLocation(type: .livingTreeCavity))

            #expect(try persistence.load()?.hive.location.type == .livingTreeCavity)
            #expect(
                try Data(contentsOf: kept) == unreadable,
                "the new colony must not have been written over the old one"
            )
        }
    }

    @Test("A second unreadable save does not replace the first")
    func secondUnreadableSaveTakesTheNextName() throws {
        try withDirectory { directory in
            let persistence = GamePersistence(directory: directory)
            let first = try saveFromALaterBuild()
            try first.write(to: persistence.saveURL)
            _ = GameStore.load(persistence: persistence, clock: { self.epoch })

            let second = Data("not a colony at all".utf8)
            try second.write(to: persistence.saveURL)
            _ = GameStore.load(persistence: persistence, clock: { self.epoch })

            #expect(
                try Data(contentsOf: directory.appendingPathComponent("colony.unreadable.json"))
                    == first
            )
            #expect(
                try Data(contentsOf: directory.appendingPathComponent("colony.unreadable-2.json"))
                    == second
            )
        }
    }

    @Test("No save at all is a first run, not an error")
    func noSaveIsNotAnError() throws {
        try withDirectory { directory in
            let store = GameStore.load(
                persistence: GamePersistence(directory: directory), clock: { self.epoch }
            )
            #expect(store.needsSetup)
            #expect(store.lastError == nil)
            #expect(
                !FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(GamePersistence.unreadableFileName).path
                )
            )
        }
    }

    // MARK: - Held

    /// Where the file can be neither read nor moved, nothing is written at
    /// all: a session that is not saved is a small loss, and a colony written
    /// over is not recoverable.
    @Test("A save that can be neither read nor moved is never written over")
    func unmovableSaveHoldsEveryWrite() {
        let persistence = UnmovablePersistence()
        let store = GameStore.load(persistence: persistence, clock: { self.epoch })

        #expect(store.lastError == GameStore.heldMessage)

        store.startNewGame(at: HiveLocation(type: .livingTreeCavity))
        store.catchUp()

        #expect(persistence.saveCount == 0, "nothing may be written over it")
        #expect(store.lastError == GameStore.heldMessage, "and the player is still told")
    }

    // MARK: - The other doors a save comes in by

    /// The watch writes what the phone sends straight to its own save, after
    /// decoding it — so it decodes with the same tolerance as a load, and a
    /// phone on a build with a config key the watch has not heard of, or the
    /// other way about, still gets its colony across.
    @Test("A transfer missing a config key is still written")
    func transferMissingAKeyIsWritten() throws {
        try withDirectory { directory in
            let original = colony()
            let older = try withoutConfigKey(
                "wildPatchDensity", in: GamePersistence.encodeForTransfer(original)
            )

            let persistence = GamePersistence(directory: directory)
            try persistence.write(transferred: older)

            #expect(try persistence.load() == original)
        }
    }

    /// A backup is a `Simulation` inside an envelope, decoded by the same
    /// types, so a `.flowerhive` written by an older build opens too.
    @Test("A backup missing a config key still opens")
    func archiveMissingAKeyOpens() throws {
        let archive = SaveArchive(exportedAt: epoch, simulation: colony())
        let data = try archive.encode()

        var document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let simulation = try JSONSerialization.data(
            withJSONObject: try #require(document["simulation"])
        )
        document["simulation"] = try JSONSerialization.jsonObject(
            with: withoutConfigKey("wildPatchDensity", in: simulation)
        )

        let opened = try SaveArchive.decoded(
            from: JSONSerialization.data(withJSONObject: document)
        )
        #expect(opened == archive)
    }

    private func withoutConfigKey(_ key: String, in data: Data) throws -> Data {
        var document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var config = try #require(document["config"] as? [String: Any])
        #expect(config.removeValue(forKey: key) != nil, "there was no \(key) to remove")
        document["config"] = config
        return try JSONSerialization.data(withJSONObject: document)
    }
}

/// A save that cannot be read, in a place it cannot be moved from — which is
/// what the protocol's default `setAsideUnreadableSave()` says of any
/// persistence that does not implement it.
private final class UnmovablePersistence: GamePersisting, @unchecked Sendable {

    struct Unreadable: Error {}

    private(set) var saveCount = 0

    func save(_ simulation: Simulation) throws { saveCount += 1 }
    func load() throws -> Simulation? { throw Unreadable() }
    func clear() throws {}
}
