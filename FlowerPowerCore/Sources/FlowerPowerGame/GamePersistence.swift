//
//  GamePersistence.swift
//  FlowerPowerGame
//
//  Saving is deliberately boring: one JSON file in a directory, written
//  atomically.
//
//  It is plain `Codable` rather than SwiftData because the simulation is
//  already a value type that round-trips exactly — there is a test that proves
//  a save and reload does not change what happens next. Introducing a
//  persistence framework here would add a translation layer between the engine
//  and its own save file for no benefit.
//
//  The directory is injected rather than looked up. On Apple platforms the
//  default is an App Group container, so the phone, the watch app and the
//  widget extension on a *single device* all read the same file. Elsewhere —
//  the Windows sessions the engine is tuned from, and every test — it is
//  Application Support or a temporary directory. Keeping the lookup out of the
//  type is what lets this layer be tested at all.
//
//  A note on the App Group, because it is easy to get wrong: an App Group is
//  shared between processes on one device, never between devices. The watch
//  cannot read the phone's save through it. See `WatchLink` for how the save
//  actually crosses.
//
//  CloudKit sync is the natural next step, and slots in behind this protocol.
//

import Foundation
import FlowerPowerCore

public protocol GamePersisting: Sendable {
    func save(_ simulation: Simulation) throws
    func load() throws -> Simulation?
    func clear() throws

    /// Something that changes whenever the stored colony changes, so a holder
    /// of a simulation in memory can tell whether the save is still the one it
    /// wrote.
    ///
    /// This exists because the save file has more than one writer. A tapped
    /// notification action, a widget button and a Shortcut all act on the file
    /// with no interface running, and `GameStore` holds the colony in memory
    /// and writes over the file on every catch-up — so without a way to ask
    /// this question the store silently loses the player's decision. See
    /// `GameStore.catchUp()`.
    ///
    /// A token rather than a date deliberately: the store never compares two
    /// saves for age, it only asks "is this still mine?", and a persistence
    /// with no timestamps to offer — an in-memory double, and a CloudKit
    /// backing later — can answer that with a counter or a record version.
    ///
    /// - Returns: nil where there is nothing stored, which is not the same as
    ///   an unchanged save.
    func changeToken() throws -> String?

    /// Moves a stored colony that could not be read out of the way, keeping
    /// every byte of it, so that a colony started in its place cannot be
    /// saved over it.
    ///
    /// What `GameStore.load` does when `load()` throws. A save this build
    /// cannot read may be one a later build can, or one somebody can mend by
    /// hand; either way it is months of somebody's walks, and it is not this
    /// build's to delete.
    ///
    /// - Returns: the name it was kept under, or nil when nothing was stored.
    func setAsideUnreadableSave() throws -> String?
}

extension GamePersisting {

    /// A persistence that cannot tell says so, and a store over it simply
    /// never reloads — which is the behaviour every one of them had before
    /// this existed.
    public func changeToken() throws -> String? { nil }

    /// A persistence that cannot move a save aside says so, and a store over
    /// it then saves nothing rather than risk writing over the colony it could
    /// not read. The safe answer is the default one on purpose: a double that
    /// forgets this method must not quietly become the old behaviour.
    public func setAsideUnreadableSave() throws -> String? {
        throw SetAsideUnsupported()
    }
}

/// Thrown by a persistence with nowhere to keep an unreadable save.
public struct SetAsideUnsupported: Error, LocalizedError {
    public var errorDescription: String? { "there is nowhere to keep the old save" }
}

public struct GamePersistence: GamePersisting {

    /// Shared between the app, the watch app and the widget extension on a
    /// single device. Must match the App Group capability enabled on each
    /// target in Xcode — see `project.yml`.
    public static let appGroupIdentifier = "group.com.linwoodtechnologies.flowerpower"

    public static let fileName = "colony.json"

    /// Directory the save file lives in.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The shared container on Apple platforms, Application Support elsewhere.
    public init() {
        self.init(directory: Self.defaultDirectory())
    }

    public var saveURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    /// `FileManager.default` is looked up per call rather than stored, because
    /// `FileManager` is not `Sendable` and holding one would make this type
    /// unsafe to pass across isolation domains — which it needs to be, since
    /// the watch extension and the widget both read through it.
    public static func defaultDirectory() -> URL {
        let manager = FileManager.default

        #if canImport(Darwin)
        if let shared = manager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return shared
        }
        #endif

        // No App Group provisioned, or not an Apple platform. The game still
        // works; it is simply not shared with the watch.
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func save(_ simulation: Simulation) throws {
        let data = try Self.encoder().encode(simulation)
        let url = saveURL

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Atomic, so a crash mid-write cannot leave a half-written colony.
        try data.write(to: url, options: .atomic)
    }

    public func load() throws -> Simulation? {
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Self.adopted(try Self.decoder().decode(Simulation.self, from: Data(contentsOf: url)))
    }

    /// Gives a colony saved before the world existed a world to live in.
    ///
    /// **Here rather than in `GameStore.load`**, which is the other obvious
    /// place, because the store is not the only thing that opens a save. The
    /// widget, the watch's complication, the App Intents and the phone's
    /// side of the watch link all call `GamePersistence().load()` directly and
    /// build a snapshot from what comes back — so a migration in the store
    /// would mean the phone's Colony tab showed a garden at 200 m while the
    /// complication on the same wrist showed the same colony at 800. This is
    /// the one door every reader already goes through.
    ///
    /// Everything it does is in `Simulation.adoptTerrainIfMissing()`, in the
    /// engine, where it can be tested without a filesystem. This decides only
    /// *when*.
    ///
    /// The result is not written back here. The next ordinary save records it,
    /// and until then the world is derived the same way from the same saved
    /// state every time it is read — so a reader that never writes, like the
    /// widget, sees exactly what the app sees.
    static func adopted(_ simulation: Simulation) -> Simulation {
        var simulation = simulation
        simulation.adoptTerrainIfMissing()
        // A catch-up ceiling written by an older build is that build's
        // default rather than anybody's decision, and left alone it would
        // keep every existing colony on a fortnight while new ones get a
        // year. Here for the same reason the terrain is: every reader of a
        // save comes through this door, so the widget and the app agree.
        if SimClock.earlierDefaultMaxCatchUpDays.contains(simulation.catchUpCeilingDays) {
            simulation.catchUpCeilingDays = SimClock.defaultMaxCatchUpDays
        }
        return simulation
    }

    public func clear() throws {
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Where an unreadable save is kept, beside the save itself.
    public static let unreadableFileName = "colony.unreadable.json"

    /// Renames the save to `colony.unreadable.json` in the same directory.
    ///
    /// A rename, so it is atomic and costs nothing however large the colony,
    /// and it stays in the App Group container with everything else. A second
    /// unreadable save never replaces the first: it takes the next free name
    /// — `colony.unreadable-2.json` and so on — because the first may be the
    /// older and better colony.
    public func setAsideUnreadableSave() throws -> String? {
        let manager = FileManager.default
        let url = saveURL
        guard manager.fileExists(atPath: url.path) else { return nil }

        var destination = directory.appendingPathComponent(Self.unreadableFileName)
        var number = 2
        while manager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("colony.unreadable-\(number).json")
            number += 1
        }

        try manager.moveItem(at: url, to: destination)
        return destination.lastPathComponent
    }

    /// The file's modification date and length, together.
    ///
    /// Either alone would be too weak. A colony's JSON is very nearly the same
    /// length from one day to the next, so the length cannot see an ordinary
    /// save; and a filesystem's timestamp resolution is coarser than the gap
    /// between two writes made in the same second, so the date cannot either.
    /// Together they miss only a save that lands inside that resolution *and*
    /// happens to encode to exactly the same number of bytes — and the cost of
    /// missing one is a single lost decision rather than a store that stays
    /// wrong, because the next write re-records the token.
    ///
    /// Reading a modification date is a required-reason API on Apple
    /// platforms: C617.1, "declaring the file timestamp for a file inside the
    /// app container". It belongs in `PrivacyInfo.xcprivacy`.
    public func changeToken() throws -> String? {
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        // The date's bit pattern rather than its description, so nothing about
        // the token depends on how a double happens to be formatted.
        return "\(modified.bitPattern):\(size)"
    }

    // MARK: - Crossing between devices

    /// Encodes a simulation for transport to the watch.
    ///
    /// Separate from `save` because the destination is a wire rather than a
    /// file, and because the watch writes what arrives into its *own*
    /// container — the bytes are the only thing the two devices share.
    public static func encodeForTransfer(_ simulation: Simulation) throws -> Data {
        try encoder().encode(simulation)
    }

    public static func decodeTransfer(_ data: Data) throws -> Simulation {
        // Migrated on arrival for the same reason as `load`: a colony that
        // crosses from an old build on the phone to a new one on the watch
        // must find the same country on both.
        adopted(try decoder().decode(Simulation.self, from: data))
    }

    /// Writes bytes received from another device straight to the save file.
    public func write(transferred data: Data) throws {
        // Decode first: a corrupt payload must not overwrite a good save.
        _ = try Self.decodeTransfer(data)

        let url = saveURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

/// Non-persistent store for previews and tests.
public final class InMemoryPersistence: GamePersisting, @unchecked Sendable {

    private var stored: Simulation?
    private let lock = NSLock()

    /// Counts saves, so a test can assert that a player action persisted.
    public private(set) var saveCount = 0

    /// Counts loads, so a test can assert the opposite of a reload: that a
    /// store with no reason to go back to the save did not go back to it.
    public private(set) var loadCount = 0

    public init(initial: Simulation? = nil) {
        self.stored = initial
    }

    public func save(_ simulation: Simulation) throws {
        lock.lock(); defer { lock.unlock() }
        stored = simulation
        saveCount += 1
    }

    public func load() throws -> Simulation? {
        lock.lock(); defer { lock.unlock() }
        loadCount += 1
        return stored
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }

    /// The save count, which is all a counter needs to be: it changes on every
    /// write and on nothing else, which is exactly the question being asked.
    public func changeToken() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard stored != nil else { return nil }
        return String(saveCount)
    }
}

/// Persistence that always fails, for testing that a save failure is surfaced
/// to the player without interrupting play.
public struct FailingPersistence: GamePersisting {

    public struct Failure: Error, LocalizedError {
        public var errorDescription: String? { "the disk is full" }
    }

    public init() {}

    public func save(_ simulation: Simulation) throws { throw Failure() }
    public func load() throws -> Simulation? { throw Failure() }
    public func clear() throws { throw Failure() }

    /// Fails like everything else here, so a store over it has to cope with
    /// not being able to find out whether its save is current — which is the
    /// case that must not be allowed to throw away the colony in memory.
    public func changeToken() throws -> String? { throw Failure() }

    /// And this, so a store over it is the case where the save can neither be
    /// read nor moved, and must then write nothing.
    public func setAsideUnreadableSave() throws -> String? { throw Failure() }
}
