//
//  StoreAuditTests.swift
//  FlowerPowerGameTests
//
//  Store bugs found auditing a month of play on a phone, 2026-10-24.
//

import Foundation
import Testing
import FlowerPowerCore
@testable import FlowerPowerGame

@MainActor
@Suite("Store audit regressions")
struct StoreAuditTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func days(_ count: Double) -> TimeInterval {
        count * Double(SimClock.ticksPerDay) * SimClock.defaultRealSecondsPerTick
    }

    /// A save that would not decode looked exactly like no save at all, and
    /// the introduction's site picker then wrote a fresh colony over it.
    @Test("A save that will not load is reported, not treated as a first run in silence")
    func unreadableSaveIsReported() {
        let store = GameStore.load(persistence: FailingPersistence())
        #expect(store.needsSetup)
        #expect(store.lastError != nil)
    }

    /// The new-phone case: a backup opened during the introduction was never
    /// saved, and choosing a site afterwards replaced it.
    @Test("Restoring a backup during the introduction ends it and saves the colony")
    func restoreDuringSetupIsKept() throws {
        let persistence = InMemoryPersistence()
        let store = GameStore.load(persistence: persistence, clock: { [epoch] in epoch })
        #expect(store.needsSetup)

        let backup = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 9
        )
        store.restore(from: SaveArchive(simulation: backup))

        #expect(!store.needsSetup)
        #expect(try persistence.load() != nil)
    }

    /// The live ticker raised a full-screen "While you were away" every
    /// simulated day, about the last hour, over whatever the player was doing.
    @Test("The live ticker never raises a catch-up report; coming back does")
    func liveTicksDoNotReport() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 3
        )
        var now = epoch
        let store = GameStore(
            simulation: simulation, persistence: InMemoryPersistence(), clock: { now }
        )

        now = epoch.addingTimeInterval(days(2))
        store.catchUp(reporting: false)
        #expect(store.pendingReport == nil)

        now = epoch.addingTimeInterval(days(4))
        store.catchUp()
        #expect(store.pendingReport != nil)
    }

    @Test("A report not yet read is added to, not replaced")
    func unreadReportAccumulates() throws {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 3
        )
        var now = epoch.addingTimeInterval(days(2))
        let store = GameStore(
            simulation: simulation, persistence: InMemoryPersistence(), clock: { now }
        )
        store.catchUp()
        let first = try #require(store.pendingReport)

        now = epoch.addingTimeInterval(days(5))
        store.catchUp()
        let second = try #require(store.pendingReport)
        #expect(second.daysSimulated > first.daysSimulated)
    }

    /// A siege and a swarm in the same background refresh made one
    /// notification, and the next refresh, comparing against a colony that
    /// already had both, made none.
    @Test("Every decision that opened in one refresh is news")
    func everyDecisionIsNews() {
        let before = ColonyNews.Facts(status: .steady, day: 10)
        let after = ColonyNews.Facts(
            status: .steady,
            pendingSwarm: PendingSwarm(startedOnDay: 10, departsOnDay: 18),
            day: 10,
            feedDecisionOpen: true
        )
        let news = ColonyNews.all(before: before, after: after)
        #expect(news.map(\.identifier).contains("swarm-10"))
        #expect(news.contains { $0.identifier.hasPrefix("feed-") })
        #expect(ColonyNews.between(before: before, after: after)?.identifier == "swarm-10")
    }

    @Test("A catch-up off the main actor lands exactly the colony one on it would")
    func backgroundCatchUpMatches() async {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 5
        )
        let later = epoch.addingTimeInterval(days(3))
        let here = GameStore(simulation: simulation, persistence: InMemoryPersistence(), clock: { later })
        let away = GameStore(simulation: simulation, persistence: InMemoryPersistence(), clock: { later })

        here.catchUp()
        await away.catchUpInBackground()

        #expect(here.snapshot == away.snapshot)
        #expect(here.pendingReport == away.pendingReport)
    }

    /// The ticker runs every twenty seconds and a tick lasts five minutes.
    @Test("A catch-up with no tick due writes nothing")
    func idleCatchUpDoesNotSave() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 5
        )
        let persistence = InMemoryPersistence()
        var now = epoch.addingTimeInterval(days(1))
        let store = GameStore(simulation: simulation, persistence: persistence, clock: { now })
        store.catchUp()
        let saves = persistence.saveCount

        now = now.addingTimeInterval(20)
        store.catchUp(reporting: false)
        #expect(persistence.saveCount == saves)
    }
}
