//
//  SaveArchive.swift
//  FlowerPowerGame
//
//  The whole colony in a file the player can keep.
//
//  The save lives in an App Group container, which means it is inside the app
//  and nowhere else: delete the app and the colony is gone, get a new phone
//  without a restored backup and the colony is gone. A colony is months of
//  real walks and real photographs, so having no way at all to get one off the
//  device is the sort of gap that is only noticed once. There is no server and
//  no account to lean on — see `GamePersistence` for why that is deliberate —
//  so the answer is the same one sharing a flower uses: a self-contained file
//  through the share sheet.
//
//  Built to the pattern `FlowerShare` and `SwarmShare` established, because a
//  file that travels has the same three problems wherever it comes from:
//
//  - It needs its own identifier and extension, declared in `project.yml`, or
//    tapping one does nothing at all.
//  - It needs a version, so a file written by a later build is refused with a
//    sentence rather than a decode error.
//  - It arrives untrusted. A `.flowerhive` may be truncated, hand-edited or
//    built to be hostile.
//
//  Where this differs from the other two is what it costs to be wrong. A
//  flower is additive and a swarm founds a colony beside the garden; a restore
//  *replaces* the colony on the device. So nothing here restores anything —
//  the type decodes and describes, and `GameStore.restore(from:)` is called
//  only after the interface has told the player what they are about to lose.
//
//  One thing this is not: it is not sync. Two phones each with a copy of the
//  same colony will diverge the moment either is opened, and whichever file is
//  opened last wins. CloudKit behind `GamePersisting` is the answer to that
//  problem; this is the answer to losing the colony entirely.
//

import Foundation
import FlowerPowerCore

public struct SaveArchive: Codable, Equatable, Sendable, Identifiable {

    /// Bumped when the shape changes incompatibly. Separate from the app's own
    /// version, which is recorded alongside it and is only ever informational:
    /// the question "can this build read this file" must not depend on
    /// parsing a marketing version string.
    public static let currentFormatVersion = 1

    /// Filename extension and uniform type identifier. Must match the document
    /// type declared in `project.yml`; a mismatch is silent and shows up as
    /// backups that will not open.
    public static let fileExtension = "flowerhive"
    public static let typeIdentifier = "com.kylepeterson.flowerpower.save"

    /// A save is JSON and grows with the colony — every bee, every patch, the
    /// whole lineage. A large one is a few hundred kilobytes; this is far past
    /// anything the engine produces and far short of a file that could not be
    /// decoded on a phone.
    public static let maximumBytes = 16 * 1024 * 1024

    public var formatVersion: Int
    /// Identifies this backup. Only used by the interface — it is what makes
    /// an archive presentable as a sheet — and by anything that wants to
    /// notice the same file being opened twice.
    public var id: String
    /// The app that wrote it, for a person reading a file they found in a
    /// folder a year from now. Optional because the package has no reliable
    /// way to know it off a phone.
    public var appVersion: String?
    /// Whole seconds. The encoder is ISO-8601, matching the rest of the
    /// house, and ISO-8601 has no sub-second field — so a fractional
    /// `exportedAt` would come back as a different value and an archive would
    /// not equal itself after a round trip.
    public var exportedAt: Date
    /// The colony, entire.
    public var simulation: Simulation

    public init(
        formatVersion: Int = SaveArchive.currentFormatVersion,
        id: String = UUID().uuidString,
        appVersion: String? = SaveArchive.currentAppVersion,
        exportedAt: Date = Date(),
        simulation: Simulation
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.appVersion = appVersion
        self.exportedAt = exportedAt.roundedToSecond
        self.simulation = simulation
    }

    /// `CFBundleShortVersionString`, which `project.yml` sets from
    /// `MARKETING_VERSION`. Nil off a phone, which is every test and every
    /// Windows session, and that is fine: the field is a note to a reader.
    public static var currentAppVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // MARK: - What is in it

    /// Enough to tell the player what they are about to restore, without the
    /// interface having to reach into a `Simulation` — which it is not allowed
    /// to do, and which is the whole point of `GameStore`.
    public struct Summary: Equatable, Sendable {
        public let day: Int
        public let season: Season
        public let status: ColonyStatus
        public let beeCount: Int
        public let flowerCount: Int
        public let generation: Int

        // No formatted sentence here on purpose. `RestoreBackupView` lays the
        // fields out against the same fields of the colony on the phone, which
        // is the comparison a player actually has to make, and a prose summary
        // would be a second way of saying it with no caller.
    }

    /// Computes the whole snapshot, which is more work than a label needs and
    /// happens once when a file is opened.
    public var summary: Summary {
        let snapshot = simulation.snapshot()
        return Summary(
            day: snapshot.day,
            season: snapshot.season,
            status: snapshot.status,
            beeCount: snapshot.population.total,
            flowerCount: snapshot.patches.count,
            generation: simulation.world.lineage.generation
        )
    }

    // MARK: - Reading and writing

    public enum Failure: Error, LocalizedError, Equatable {
        case notASaveFile
        case fromANewerVersion(Int)
        case tooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .notASaveFile:
                return "That does not look like a FlowerPower backup."
            case .fromANewerVersion:
                return "This backup came from a newer version of FlowerPower. Update to open it."
            case .tooLarge:
                return "That backup is too large to open."
            }
        }
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

    public func encode() throws -> Data {
        try Self.encoder().encode(self)
    }

    /// Reads a backup somebody opened.
    ///
    /// The size check comes before the decode, because a decoder handed a
    /// hundred megabytes of nested JSON will happily spend the phone's memory
    /// finding out it is not a colony.
    ///
    /// There is no `validated()` here, unlike the other two travelling types,
    /// and the reason is worth being explicit about: a save is not a handful
    /// of fields that can be clamped into range but the entire engine state,
    /// and a clamp over thousands of bees would be a second, unverified copy
    /// of every invariant the systems already maintain. What guards this
    /// instead is that a save decodes as a `Simulation` at all — the strictly
    /// typed, non-optional shape of `World` refuses most of what a corrupt or
    /// hand-edited file could be — and that the engine is written to survive
    /// states it did not produce, since it has to survive its own old saves.
    public static func decoded(from data: Data) throws -> SaveArchive {
        guard data.count <= maximumBytes else {
            throw Failure.tooLarge(data.count)
        }

        if let archive = try? decoder().decode(SaveArchive.self, from: data) {
            guard archive.formatVersion <= currentFormatVersion else {
                throw Failure.fromANewerVersion(archive.formatVersion)
            }
            return archive
        }

        // It would not decode. That is usually because it is not a backup, and
        // occasionally because it is one from a build that changed the *shape*
        // of the file as well as the version — in which case the player is on
        // an old build and needs telling to update, not telling their backup
        // is corrupt. So the version is looked for on its own before giving
        // up. Only in this order, because it means a good file is parsed once
        // rather than twice.
        if let probe = try? decoder().decode(VersionProbe.self, from: data),
           probe.formatVersion > currentFormatVersion {
            throw Failure.fromANewerVersion(probe.formatVersion)
        }

        throw Failure.notASaveFile
    }

    /// Just the version field, so a future file can be recognised as one
    /// before the rest of it fails to decode.
    private struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    // MARK: - Naming the file

    /// What to call the file in the share sheet. Dated, because the player
    /// will have more than one and the only thing that distinguishes them is
    /// when they were taken.
    ///
    /// Also available without an archive in hand, because `exportArchive()`
    /// hands the interface bytes rather than a value — and decoding those
    /// bytes back into an archive just to read a filename off it would be
    /// absurd.
    public static func suggestedFileName(exportedAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "FlowerPower \(formatter.string(from: exportedAt)).\(fileExtension)"
    }

    public var suggestedFileName: String {
        Self.suggestedFileName(exportedAt: exportedAt)
    }
}

// MARK: - Previews

extension SaveArchive {

    /// A backup of a small colony, for previews.
    ///
    /// Here rather than in the app so that the restore screen's preview does
    /// not have to reach into `GameStore.simulationForTransfer`, which views
    /// are not allowed to touch — a rule a preview should not be the one
    /// exception to.
    public static func preview(daysToRun: Int = 45) -> SaveArchive {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var simulation = Simulation.newGame(
            at: HiveLocation(
                coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                type: .livingTreeCavity
            ),
            startingAt: start,
            seed: 42
        )
        for index in 0..<6 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "preview-\(index)",
                species: FlowerCatalogue.whiteClover,
                confidence: 0.8,
                coordinate: nil,
                takenAt: start
            )
        }
        for _ in 0..<daysToRun { _ = simulation.stepDay() }

        return SaveArchive(
            appVersion: "1.0",
            exportedAt: start.addingTimeInterval(Double(daysToRun) * 2 * 3600),
            simulation: simulation
        )
    }
}

private extension Date {
    /// Whole seconds, which is all ISO-8601 carries. See `exportedAt`.
    var roundedToSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
