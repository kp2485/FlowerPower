//
//  FrozenSaveTests.swift
//  FlowerPowerGameTests
//
//  Saves written by earlier builds, kept exactly as they were written.
//
//  A save that will not decode is the worst bug this game can have: the app
//  finds nothing it can read, and the player's colony and garden are gone.
//  It happened once already, on 2026-09-16, when nine constants were added to
//  `SimulationConfig` and the compiler's decoder refused every save without
//  them. Nothing caught it, because every test encoded and decoded with the
//  same build.
//
//  These files are the fix for that: written by a real build on the day in
//  their name and never touched again. A change that adds a stored property
//  without a default to `Bee`, `Hive`, `Comb`, `FlowerPatch` or anything else
//  in a save fails here, not on a phone. When one does, make the new field
//  optional or give it a `decodeIfPresent` default — do not regenerate the
//  file. Add a new frozen save beside it when the shape of a save changes on
//  purpose.
//

import Foundation
import Testing
import FlowerPowerCore
@testable import FlowerPowerGame

@Suite("Frozen saves")
struct FrozenSaveTests {

    private func persistence(holding name: String) throws -> GamePersistence {
        let source = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("frozen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: source, to: directory.appendingPathComponent(GamePersistence.fileName)
        )
        return GamePersistence(directory: directory)
    }

    @Test("A save written on 2026-10-24 still opens, whole, and plays on")
    func october2026() throws {
        let persistence = try persistence(holding: "frozen-2026-10-24")
        var simulation = try #require(try persistence.load())

        #expect(simulation.clock.day == 200)
        #expect(simulation.patches.count == 11)
        #expect(!simulation.wildPatches.isEmpty)
        let shared = simulation.patches.first { $0.photoLocalIdentifier == "shared:frozen-share" }
        #expect(shared?.isShared == true)
        #expect(shared?.sharedBy == "A friend")
        #expect(simulation.hasImported(shareID: "frozen-share"))

        // And it is a colony, not just a file that parsed.
        let snapshot = simulation.snapshot()
        #expect(snapshot.status.isAlive)
        simulation.advance(to: simulation.clock.date(atTick: simulation.clock.tick + 48))
        #expect(simulation.clock.day == 202)

        // Round trip through this build, which is what the next launch does.
        try persistence.save(simulation)
        #expect(try persistence.load() != nil)
    }
}
