//
//  ForageNewsTests.swift
//  FlowerPowerGameTests
//
//  The first player to live with the game's notifications said the only thing
//  they ever saw, in the morning report and on opening the app, was that
//  flowers had gone out of season. Two causes, both held here:
//
//  - the engine announced a flower out of season every day it stayed out of
//    season, which filled the catch-up report's sixty places with nothing;
//  - the morning report and the colony news both led with the headline, and
//    the headline of a colony with a resting garden is about the garden.
//

import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

@Suite("Flowers going over is not news")
struct ForageNewsTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// A colony with a garden of spring flowers and nothing else.
    private func springGarden(flowers: Int = 9) throws -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 33
        )
        let spring = try #require(FlowerCatalogue.all.first { $0.bloomSeasons == [.spring] })
        for index in 0..<flowers {
            _ = simulation.registerPhotograph(
                photoLocalIdentifier: "spring-\(index)",
                species: spring,
                confidence: 0.9,
                takenAt: epoch
            )
        }
        return simulation
    }

    private func outOfBloomEvents(_ events: [SimEvent]) -> Int {
        events.filter {
            if case .patchOutOfBloom = $0 { return true }
            return false
        }.count
    }

    // MARK: - The engine says it once

    @Test("A flower going out of season is announced on the day it happens, and not again")
    func announcedOnce() throws {
        var simulation = try springGarden(flowers: 3)

        // Through the whole of spring and well into summer.
        var perDay: [Int: Int] = [:]
        while simulation.day < Season.daysPerSeason + 20 {
            let day = simulation.day
            let count = outOfBloomEvents(simulation.stepDay())
            if count > 0 { perDay[day, default: 0] += count }
        }

        // Once per stand, all on the one day the season turned. The country
        // around the nest has wild stands of its own and they keep the same
        // calendar, and a stand the bees had already worked out says nothing,
        // so "at most".
        let stands = 3 + simulation.world.patches.filter(\.isWild).count
        #expect(perDay.count <= 1, "announced on \(perDay.keys.sorted()) — it should be one day")
        #expect(perDay.values.reduce(0, +) <= stands)
    }

    @Test("It is not a highlight of the catch-up report")
    func notAHighlight() {
        #expect(!SimEvent.patchOutOfBloom(EntityID(rawValue: 1)).isHighlight)
    }

    @Test("A summer away with a spring garden does not fill the report with flowers")
    func reportIsNotFlooded() throws {
        var simulation = try springGarden()
        // Five real days, which is about two simulated months: into summer,
        // with every flower in the garden out of season for most of it.
        let report = simulation.advance(to: epoch.addingTimeInterval(5 * 24 * 3600))

        #expect(outOfBloomEvents(report.highlights) == 0)
    }

    // MARK: - The notifications do not lead with it

    /// A snapshot whose headline is one of the forage sentences: a colony in
    /// flying weather, outside winter, with a garden that is all out of
    /// season.
    ///
    /// `quiet` asks for a day with no alert but the garden's, too. Since the
    /// brood nest has been kept for the queen (2026-09-24) this colony fills
    /// it, and on the first forage-headline day, 95, it also carried "Nest Is
    /// Full" — a true alert, and one the digest is right to send.
    private func restingGardenSnapshot(quiet: Bool = false) throws -> ColonySnapshot {
        var simulation = try springGarden()
        while simulation.day < Season.daysPerSeason + 5 { _ = simulation.stepDay() }
        // Look for a day the headline really is about the garden, since
        // weather and the colony's own troubles outrank it.
        for _ in 0..<60 {
            // The country grows wild forage that is in bloom when the garden
            // is not, and the headline counts it. Taken out, so that what is
            // left is the state this suite is about: nothing to work.
            simulation.world.patches.removeAll(where: \.isWild)
            let snapshot = simulation.snapshot()
            let onlyTheGarden = snapshot.alerts.allSatisfy { $0.kind == .noForage }
            if snapshot.headlineIsAboutForage, !quiet || onlyTheGarden { return snapshot }
            _ = simulation.stepDay()
        }
        simulation.world.patches.removeAll(where: \.isWild)
        return simulation.snapshot()
    }

    @Test("The three forage sentences are recognised, and nothing else is")
    func recognised() throws {
        let snapshot = try restingGardenSnapshot()
        try #require(snapshot.headlineIsAboutForage,
                     "no day in sixty had a forage headline; the fixture needs another look")
        #expect(snapshot.headline == ColonySnapshot.ForageHeadline.nothingInBloom
                || snapshot.headline == ColonySnapshot.ForageHeadline.goneOver)
    }

    @Test("The morning report does not open with the garden")
    func digestDoesNotLeadWithForage() throws {
        let snapshot = try restingGardenSnapshot()
        try #require(snapshot.headlineIsAboutForage)

        // Something did happen, so there is a report to write.
        var report = CatchUpReport()
        report.record(.swarmed(beesLost: 120))
        report.ticksSimulated = SimClock.ticksPerDay

        let digest = try #require(DailyDigest.make(from: report, snapshot: snapshot))
        #expect(!digest.body.contains(ColonySnapshot.ForageHeadline.nothingInBloom))
        #expect(!digest.body.contains(ColonySnapshot.ForageHeadline.goneOver))
        #expect(digest.body.contains("A swarm left."))
    }

    @Test("A resting garden is not by itself a reason to send a morning report")
    func restingGardenAloneSendsNothing() throws {
        let snapshot = try restingGardenSnapshot(quiet: true)
        try #require(snapshot.headlineIsAboutForage)
        try #require(snapshot.status >= .steady)
        try #require(snapshot.alerts.allSatisfy { $0.kind == .noForage })

        var report = CatchUpReport()
        report.ticksSimulated = SimClock.ticksPerDay

        #expect(DailyDigest.make(from: report, snapshot: snapshot) == nil)
    }

    @Test("Colony news reports a decline, not the garden")
    func newsIsTheDecline() throws {
        var after = ColonyNews.Facts(
            status: .struggling,
            headline: ColonySnapshot.ForageHeadline.goneOver,
            patchCount: 9, patchesInBloom: 0
        )
        after.headlineIsAboutForage = true
        let news = try #require(ColonyNews.between(
            before: ColonyNews.Facts(status: .steady, patchCount: 9, patchesInBloom: 9),
            after: after
        ))

        #expect(!news.body.contains("gone over"))
        #expect(!news.body.contains("Photograph"))
        #expect(news.title == "The colony is struggling")
    }
}
