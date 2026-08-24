//
//  GamePersistence.swift
//  FlowerPower
//
//  Saving is deliberately boring: one JSON file in a shared App Group
//  container, written atomically.
//
//  It lives in the App Group rather than the app's own container so the watch
//  can read the same file, and it is plain `Codable` rather than SwiftData
//  because the simulation is already a value type that round-trips exactly —
//  there is a test that proves a save and reload does not change what happens
//  next. Introducing a persistence framework here would add a translation layer
//  between the engine and its own save file for no benefit.
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

    /// Shared with the watch extension. Must match the App Group capability
    /// enabled on both targets in Xcode.
    public static let appGroupIdentifier = "group.com.kylepeterson.flowerpower"

    public static let fileName = "colony.json"

    public init() {}

    /// `FileManager.default` is looked up per call rather than stored, because
    /// `FileManager` is not `Sendable` and holding one would make this type
    /// unsafe to pass across isolation domains — which it needs to be, since
    /// the watch extension and the widget both read through it.
    private var fileManager: FileManager { .default }

    public var saveURL: URL {
        let manager = fileManager
        let directory = manager
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        return directory.appendingPathComponent(Self.fileName)
    }

    public func save(_ simulation: Simulation) throws {
        let fileManager = self.fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(simulation)
        let url = saveURL

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Atomic, so a crash mid-write cannot leave a half-written colony.
        try data.write(to: url, options: .atomic)
    }

    public func load() throws -> Simulation? {
        let fileManager = self.fileManager
        let url = saveURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(Simulation.self, from: Data(contentsOf: url))
    }

    public func clear() throws {
        let fileManager = self.fileManager
        let url = saveURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

/// Non-persistent store for previews and tests.
public final class InMemoryPersistence: GamePersisting, @unchecked Sendable {

    private var stored: Simulation?
    private let lock = NSLock()

    public init(initial: Simulation? = nil) {
        self.stored = initial
    }

    public func save(_ simulation: Simulation) throws {
        lock.lock(); defer { lock.unlock() }
        stored = simulation
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
