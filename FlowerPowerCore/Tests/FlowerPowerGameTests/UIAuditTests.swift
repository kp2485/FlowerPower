//
//  UIAuditTests.swift
//  FlowerPowerGameTests
//
//  What an adversarial pass over the interface found, 2026-10-31, in the parts
//  of it that can be held to account without a screen.
//

import Foundation
import Testing
@testable import FlowerPowerCore
@testable import FlowerPowerGame

@MainActor
@Suite("Interface audit regressions")
struct UIAuditTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func days(_ count: Double) -> TimeInterval {
        count * Double(SimClock.ticksPerDay) * SimClock.defaultRealSecondsPerTick
    }

    private func colony(seed: UInt64 = 7) -> Simulation {
        Simulation.newGame(at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: seed)
    }

    private func dead(_ simulation: Simulation) -> Simulation {
        var simulation = simulation
        simulation.world.hive.bees.removeAll()
        return simulation
    }

    // MARK: Backups

    /// A file edited to hold 1e300 honey decoded cleanly, then trapped in
    /// `Int()` the moment the restore screen drew its summary.
    @Test("A backup with an impossible number is refused rather than opened")
    func tamperedBackupRefused() throws {
        let data = try SaveArchive(simulation: colony()).encode()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var simulation = try #require(object["simulation"] as? [String: Any])
        var clock = try #require(simulation["clock"] as? [String: Any])
        clock["tick"] = Int.max
        simulation["clock"] = clock
        object["simulation"] = simulation
        let tampered = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: SaveArchive.Failure.notASaveFile) {
            try SaveArchive.decoded(from: tampered)
        }
    }

    @Test("An ordinary backup still opens, random state and all")
    func ordinaryBackupOpens() throws {
        var simulation = colony()
        for _ in 0..<30 { _ = simulation.stepDay() }
        let archive = try SaveArchive.decoded(from: SaveArchive(simulation: simulation).encode())
        #expect(archive.simulation.clock.tick == simulation.clock.tick)
    }

    @Test("A stored hoard too big to draw is refused")
    func impossibleStoresRefused() throws {
        var simulation = colony()
        simulation.world.hive.resources[.honey] = 5e7
        let data = try SaveArchive(simulation: simulation).encode()
        #expect(throws: SaveArchive.Failure.notASaveFile) {
            try SaveArchive.decoded(from: data)
        }
    }

    @Test("Comb arithmetic cannot trap on a number no colony reaches")
    func cellsOccupiedCannotTrap() {
        var pool = ResourcePool()
        pool[.honey] = 1e300
        #expect(pool.cellsOccupied > 0)
    }

    @Test("A tick past the end of any game is clamped on the way in")
    func tickIsClamped() throws {
        let clock = SimClock(epoch: epoch)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(clock)) as? [String: Any]
        )
        object["tick"] = Int.max
        let decoded = try JSONDecoder().decode(
            SimClock.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.tick == SimClock.maximumTick)
    }

    /// The restore screen promised day 30 and the next tick delivered 180
    /// days after it, often a dead colony, with no report.
    @Test("A restored backup picks up from the day it was saved")
    func restoreResumes() {
        var backup = colony()
        for _ in 0..<30 { _ = backup.stepDay() }
        let archive = SaveArchive(simulation: backup)

        var now = epoch.addingTimeInterval(days(400))
        let store = GameStore(simulation: colony(seed: 8), persistence: InMemoryPersistence(), clock: { now })
        store.restore(from: archive)
        let restored = store.snapshot.day

        now = now.addingTimeInterval(60)
        store.catchUp(reporting: false)
        #expect(store.snapshot.day == restored)
    }

    @Test("Restoring tells the interface it is a different colony")
    func restoreCountsAsAChange() {
        let store = GameStore(simulation: colony(), persistence: InMemoryPersistence(), clock: { [epoch] in epoch })
        store.restore(from: SaveArchive(simulation: colony(seed: 9)))
        #expect(store.colonyChanges == 1)
    }

    // MARK: Saves that would not read

    /// One unreadable moment is not a bad file: a launch before first unlock
    /// cannot read a protected one at all.
    @Test("A save unreadable at launch is taken back when it can be read")
    func unreadableSaveRecovers() throws {
        let persistence = FlakyPersistence()
        try persistence.backing.save(colony())
        persistence.failsToLoad = true

        let store = GameStore.load(persistence: persistence, clock: { [epoch] in epoch })
        #expect(store.needsSetup)
        #expect(store.lastError != nil)

        store.retryUnreadableSave()
        #expect(store.needsSetup, "still unreadable, so nothing changes")
        store.catchUp()
        #expect(persistence.savesWhileLocked == 0, "and nothing is written over it")

        persistence.failsToLoad = false
        store.retryUnreadableSave()
        #expect(!store.needsSetup)
        #expect(store.lastError == nil)
    }

    // MARK: Starting again

    /// `startLiveUpdates` asked a snapshot of the dead colony whether there
    /// was anything to run, and the new one sat frozen until the next launch.
    @Test("Beginning again after a collapse starts the live view")
    func beginAgainTicks() {
        let store = GameStore(simulation: dead(colony()), persistence: InMemoryPersistence(), clock: { [epoch] in epoch })
        #expect(store.isCollapsed)
        store.startNewGame(at: HiveLocation(type: .livingTreeCavity))
        #expect(store.isRunningLiveUpdates)
        store.stopLiveUpdates()
    }

    @Test("Flowers past ring 1 stay on the map when the colony changes")
    func gardenKeepsItsRings() throws {
        var simulation = colony()
        for index in 0..<8 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "photo-\(index)",
                species: FlowerCatalogue.whiteClover, confidence: 0.9, takenAt: epoch
            )
        }
        let rings = try #require(simulation.world.terrain?.gardenRings)
        #expect(rings >= 2)

        let store = GameStore(simulation: simulation, persistence: InMemoryPersistence(), clock: { [epoch] in epoch })
        store.startNewGame(at: HiveLocation(type: .livingTreeCavity))

        let terrain = try #require(store.snapshot.terrain)
        #expect(terrain.gardenRings >= rings)
        #expect(terrain.garden.filter { $0.patchID != nil }.count == 8)
    }

    // MARK: Decisions

    /// "Make Room" is a posture, and a wasp arriving under it found the
    /// buttons gone from every surface.
    @Test("A posture that is no answer to a siege leaves the siege open")
    func unrelatedPostureDoesNotAnswer() {
        var simulation = colony()
        let threat = ActiveThreat(predator: .wasp, beganOnDay: 0, resolvesOnDay: 3)
        simulation.world.activeThreat = threat
        simulation.world.posture = .makeRoom

        #expect(!threat.isAnswered(by: .makeRoom))
        #expect(threat.isAnswered(by: threat.options[0]))
        #expect(simulation.watchSummary().decision?.kind == .siege)
    }

    @Test("Keeping the entrance open closes the question")
    func keepOpenCloses() {
        var simulation = autumnColony()
        #expect(simulation.snapshot().entranceDecisionOpen)
        simulation.decideEntrance(sealed: false)
        #expect(!simulation.snapshot().entranceDecisionOpen)
        #expect(simulation.watchSummary().decision?.kind != .entrance)
    }

    /// Said without the propolis to do it, the word turned instinct off and
    /// did nothing itself, so the colony wintered unsealed.
    @Test("Told to seal without the propolis, they seal when they have it")
    func sealWaitsForPropolis() {
        var simulation = autumnColony()
        simulation.world.hive.resources[.propolis] = 0
        simulation.decideEntrance(sealed: true)
        #expect(!simulation.world.entranceSealed)
        #expect(!simulation.snapshot().entranceDecisionOpen)

        simulation.world.hive.resources[.propolis] = simulation.config.entranceSealPropolis * 2
        _ = simulation.stepDay()
        #expect(simulation.world.entranceSealed)
    }

    private func autumnColony() -> Simulation {
        var simulation = colony()
        while simulation.snapshot().season != .autumn { _ = simulation.stepDay() }
        simulation.world.entranceSealed = false
        simulation.world.entranceDecision = nil
        return simulation
    }

    /// It reported success and changed nothing, so the watch held the answer
    /// and ignored the phone for as long as the swarm stayed pending.
    @Test("Letting a swarm go closes the question everywhere")
    func lettingGoCloses() {
        var simulation = colony()
        simulation.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        let store = GameStore(simulation: simulation, persistence: InMemoryPersistence(), clock: { [epoch] in epoch })
        #expect(store.watchSummary().decision?.kind == .swarm)

        #expect(store.apply(.letSwarmGo))
        #expect(store.watchSummary().decision?.kind != .swarm)
    }

    @Test("A swarm saved before this field existed still loads")
    func pendingSwarmFromOlderSave() throws {
        let data = Data(#"{"startedOnDay":1,"departsOnDay":5,"discouraged":false}"#.utf8)
        let swarm = try JSONDecoder().decode(PendingSwarm.self, from: data)
        #expect(!swarm.isAnswered)
    }

    @Test("A dead colony asks nothing")
    func deadColonyAsksNothing() {
        var simulation = autumnColony()
        simulation.world.hive.bees.removeAll()
        let summary = simulation.watchSummary()
        #expect(summary.decision == nil)
        #expect(summary.gauge.value == 0)
        #expect(summary.shortHeadline == ColonyStatus.collapsed.displayName)
    }

    @Test("A job nobody can do leaves the current pin alone")
    func refusedPinKeepsTheOld() throws {
        var simulation = colony()
        for _ in 0..<40 { _ = simulation.stepDay() }
        let doable = try #require(WorkerJob.allCases.first { job in
            var copy = simulation
            return copy.emphasise(job) > 0
        })
        #expect(simulation.emphasise(doable) > 0)
        let pinned = simulation.emphasisedJob

        // Nobody is left who can do anything.
        var empty = simulation
        empty.world.hive.bees.removeAll { $0.kind == .worker && $0.assignedJob == nil }
        let before = empty.world.hive.bees
        let impossible = try #require(WorkerJob.allCases.first { job in
            var copy = empty
            return job != doable && copy.emphasise(job) == 0
        })
        #expect(empty.emphasise(impossible) == 0)
        #expect(empty.world.hive.bees == before)
        #expect(pinned == doable)
    }

    // MARK: Sharing

    /// `taxon:` identifiers mean nothing to the catalogue, so a flower BioCLIP
    /// named arrived unnamed after the sender had been told otherwise.
    @Test("A flower named outside the catalogue keeps its name on the way")
    func taxonTravels() {
        let share = FlowerShare(
            speciesID: "taxon:Tulipa albanica",
            taxon: Taxon(
                family: FlowerCatalogue.whiteClover.taxon.family,
                genus: "Tulipa", specificEpithet: "albanica"
            ),
            taxonCommonName: "Albanian tulip",
            confidence: 0.8, takenAt: epoch, sharedBy: nil,
            imageData: Data([1, 2, 3])
        ).validated()

        #expect(share.speciesID == nil)
        #expect(share.displayName == "Albanian tulip")
    }

    @Test("Text from a share is capped however it is built")
    func combiningMarksAreCapped() {
        let stacked = "a" + String(repeating: "\u{0301}", count: 100_000)
        #expect(stacked.cappedForDisplay.unicodeScalars.count <= 320)
    }

    @Test("A share's identifier cannot fill the save")
    func longShareIDIsReplaced() {
        let share = FlowerShare(
            id: String(repeating: "x", count: 100_000),
            speciesID: nil, confidence: 0, takenAt: epoch, sharedBy: nil,
            imageData: Data([1])
        ).validated()
        #expect(share.id.count <= 128)
    }

    @Test("A queen's name goes with her swarm")
    func queenKeepsHerName() throws {
        var simulation = colony()
        let number = try #require(simulation.world.lineage.reigning?.number)
        simulation.nameQueen(number, "Beatrice")
        let queen = try #require(simulation.world.hive.queen)
        simulation.world.lastSwarm = DepartedSwarm(
            day: 0, queen: queen, workers: [],
            genetics: simulation.world.hive.genetics, honeyCarried: 1, queenNumber: number
        )

        let followed = try #require(simulation.followingSwarm(
            to: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2
        ))
        #expect(followed.world.lineage.reigning?.name == "Beatrice")
    }

    // MARK: What the report says

    @Test("The weather is not news, and one winter warning is enough")
    func reportStaysOnTheEvents() {
        var report = CatchUpReport()
        report.record(.weatherChanged(.rain), day: 1)
        report.record(.winterStoresLow(have: 10, need: 100), day: 2)
        report.record(.nectarFlowBegan, day: 3)
        report.record(.winterStoresLow(have: 8, need: 100), day: 4)

        #expect(report.highlights.count == 2)
        #expect(report.highlightDays == [3, 4])
    }

    @Test("Narration reads as English", arguments: [
        (SimEvent.weatherChanged(.rain), "The weather turned rainy."),
        (SimEvent.weatherChanged(.storm), "The weather turned stormy."),
        (SimEvent.attackRepelled(.toad), "The guards drove off a toad."),
        (SimEvent.attackRepelled(.robberBee), "The guards drove off robber bees."),
        (SimEvent.attacked(.opossum), "An opossum attacked the hive."),
        (SimEvent.threatEnded(.wasp), "A wasp gave up on the nest.")
    ])
    func narration(event: SimEvent, expected: String) {
        #expect(event.narration == expected)
    }

    @Test("Counts agree with themselves")
    func counted() {
        #expect(1.counted("day") == "1 day")
        #expect(0.counted("day") == "0 days")
        #expect(2.counted("larva", plural: "larvae") == "2 larvae")
    }

    @Test("The day is written the same way everywhere")
    func displayDayCountsFromOne() {
        #expect(colony().snapshot().displayDay == 1)
    }
}

/// Locked, as a protected file is before the phone's first unlock, until it
/// is told otherwise. Counts writes, because nothing may go over it meanwhile.
private final class FlakyPersistence: GamePersisting, @unchecked Sendable {

    let backing = InMemoryPersistence()
    var failsToLoad = false
    var savesWhileLocked = 0

    func save(_ simulation: Simulation) throws {
        if failsToLoad { savesWhileLocked += 1 }
        try backing.save(simulation)
    }
    func load() throws -> Simulation? {
        if failsToLoad { throw CocoaError(.fileReadNoPermission) }
        return try backing.load()
    }
    func clear() throws { try backing.clear() }
    func changeToken() throws -> String? { try backing.changeToken() }
}
