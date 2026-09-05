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
}

public struct GamePersistence: GamePersisting {

    /// Shared between the app, the watch app and the widget extension on a
    /// single device. Must match the App Group capability enabled on each
    /// target in Xcode — see `project.yml`.
    public static let appGroupIdentifier = "group.com.kylepeterson.flowerpower"

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
        return try Self.decoder().decode(Simulation.self, from: Data(contentsOf: url))
    }

    public func clear() throws {
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
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
        try decoder().decode(Simulation.self, from: data)
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
        return stored
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
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
}
