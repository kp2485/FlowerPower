//
//  AuditRegressionTests.swift
//  FlowerPowerCoreTests
//
//  Bugs found auditing a month of play on a phone, 2026-10-24, each pinned
//  by the smallest thing that showed it.
//

import Foundation
import Testing
@testable import FlowerPowerCore

@Suite("Audit regressions")
struct AuditRegressionTests {

    // MARK: - Saves

    /// The country added nine constants, and every save written before it
    /// stopped decoding: the compiler's decoder fails on a missing key.
    @Test("A save written before a constant existed still opens, and keeps its own constants")
    func configMissingAKeyStillDecodes() throws {
        var config = SimulationConfig.standard
        config.honeyPerWax = 9
        let simulation = Fixture.thrivingSimulation(config: config)

        let data = try JSONEncoder().encode(simulation)
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var stored = try #require(root["config"] as? [String: Any])
        #expect(stored.removeValue(forKey: "foundingCombCells") != nil)
        root["config"] = stored
        let older = try JSONSerialization.data(withJSONObject: root)

        let decoded = try JSONDecoder().decode(Simulation.self, from: older)
        #expect(decoded.config.honeyPerWax == 9)
        #expect(decoded.config.foundingCombCells == SimulationConfig.standard.foundingCombCells)
        #expect(decoded.world == simulation.world)
    }

    /// A backup is a file anyone can send. These values in one hung or
    /// crashed the app on every launch after restoring it.
    @Test("A clock with hostile values decodes to something that cannot hang or trap")
    func hostileClockIsClamped() throws {
        let data = try JSONEncoder().encode(SimClock(epoch: epoch))
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["maxCatchUpDays"] = Int.max
        root["realSecondsPerTick"] = 1e-300
        root["winterSpeed"] = 1e300
        root["tick"] = -5
        let hostile = try JSONSerialization.data(withJSONObject: root)

        var clock = try JSONDecoder().decode(SimClock.self, from: hostile)
        #expect(clock.tick == 0)
        #expect(clock.maxCatchUpDays <= 3650)
        let pending = clock.pendingTicks(at: .afterSimulated(days: 10_000))
        #expect(pending <= clock.maxCatchUpDays * SimClock.ticksPerDay)
        clock.resynchronize(to: .afterSimulated(days: 10_000))
    }

    // MARK: - Time

    /// Set forward to skip ahead, then put right: the colony froze until real
    /// time caught up with the tick it had reached.
    @Test("Putting the device clock back after a jump forward does not freeze the colony")
    func clockBackAfterJumpForward() {
        var simulation = Fixture.thrivingSimulation()
        simulation.advance(to: .afterSimulated(days: 30))
        let reached = simulation.clock.day

        let putBack = Date.afterSimulated(days: 2)
        let report = simulation.advance(to: putBack)
        #expect(report.ticksSimulated == 0)
        #expect(simulation.clock.day == reached)

        simulation.advance(to: putBack.addingTimeInterval(Double(SimClock.ticksPerDay) * 300))
        #expect(simulation.clock.day == reached + 1)
    }

    // MARK: - The colony

    /// No comb, nowhere to put nectar, no foraging, no flow, no comb: every
    /// colony that moved died within a fortnight with honey still in it.
    @Test("A colony that moves into a bare cavity draws comb from what it carried")
    func foundingColonyDrawsComb() {
        var simulation = Fixture.thrivingSimulation()
        simulation.relocate(to: HiveLocation(type: .livingTreeCavity))
        #expect(simulation.world.hive.comb.builtCells == 0)

        simulation.runDays(5)
        #expect(simulation.world.hive.comb.builtCells > 0)
    }

    @Test("Wild stands do not earn the badges for photographing flowers")
    func wildStandsAreNotTheGarden() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 42
        )
        #expect(!simulation.wildPatches.isEmpty, "no wild stands, so this proves nothing")
        simulation.runDays(2)
        #expect(!simulation.milestones.has(.firstFlower))
        #expect(!simulation.milestones.has(.placedToFamily))
    }

    @Test("A dead colony is written into the almanac once, not every day it is kept")
    func collapseIsChronicledOnce() {
        var almanac = Almanac()
        for day in 10..<20 {
            almanac.chronicle([.colonyCollapsed], day: day, honey: 0, lineage: Lineage())
        }
        #expect(almanac.entries.filter { $0.text == Almanac.colonyGone }.count == 1)
    }

    @Test("Starting again keeps a shared flower shared, and a faded one faded")
    func inheritedGardenKeepsItsState() {
        var old = Fixture.thrivingSimulation(patches: 0)
        _ = old.importSharedFlower(
            shareID: "share-1", photoLocalIdentifier: "shared:share-1",
            species: Fixture.clover, confidence: 0.9, takenAt: epoch, sharedBy: "Sam"
        )
        _ = old.registerPhotograph(
            photoLocalIdentifier: "photo", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        old.setDay(old.config.patchFreshDays + old.config.patchFadeDays + 5)

        let fresh = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 7,
            inheriting: old.patches, inheritedOnDay: old.clock.day,
            importedShares: old.world.importedShares
        )
        #expect(fresh.hasImported(shareID: "share-1"))
        let shared = fresh.patches.first { $0.photoLocalIdentifier == "shared:share-1" }
        #expect(shared?.isShared == true)
        #expect(shared?.sharedBy == "Sam")
        let photographed = fresh.patches.first { $0.photoLocalIdentifier == "photo" }
        #expect(photographed?.hasFaded(onDay: fresh.clock.day, config: fresh.config) == true)
    }

    // MARK: - Reports

    @Test("Two catch-ups merged read as one absence")
    func reportsMerge() {
        var first = CatchUpReport()
        first.daysSimulated = 2
        first.ticksSimulated = 48
        first.record(.swarmed(beesLost: 100))
        var second = CatchUpReport()
        second.daysSimulated = 1
        second.ticksSimulated = 24
        second.record(.queenLost)

        let merged = first.merging(second)
        #expect(merged.daysSimulated == 3)
        #expect(merged.swarmed && merged.queenLost)
    }
}
