import Testing
import Foundation
@testable import FlowerPowerCore

/// The day-by-day record behind the charts.
///
/// Three of these are about the record being trustworthy — one sample a day,
/// the numbers matching the hive, the cap holding — and two are about it being
/// harmless: the engine was balanced without it, so adding it must not move a
/// colony by a single bee, and every save written before it existed must still
/// open.
@Suite("Colony history")
struct HistoryTests {

    // MARK: - One sample a day

    @Test("A day is recorded once, at its boundary, and never mid-day")
    func oneSamplePerDay() {
        var simulation = Fixture.thrivingSimulation(seed: 1_212)
        simulation.runDays(5)

        // The first tick of a colony's life is a day boundary too, so day 0
        // is in the record and the newest day is the one just lived.
        #expect(simulation.history.samples.map(\.day) == [0, 1, 2, 3, 4])
        #expect(simulation.clock.day == 5)

        // The next tick is the day-5 boundary; the twenty-three after it are
        // not, and must add nothing.
        _ = simulation.step()
        #expect(simulation.history.samples.count == 6)
        #expect(simulation.history.lastDay == 5)

        for _ in 1..<SimClock.ticksPerDay {
            _ = simulation.step()
            #expect(simulation.history.samples.count == 6, "a sample was taken mid-day")
        }
        #expect(simulation.clock.day == 6)
    }

    @Test("Nothing is recorded before the colony has been stepped")
    func emptyBeforeTheFirstTick() {
        let simulation = Fixture.thrivingSimulation()
        #expect(simulation.history.isEmpty)
        #expect(simulation.history.firstDay == nil)
    }

    @Test("A month of days leaves a month of samples, oldest first")
    func aMonthOfDays() {
        var simulation = Fixture.thrivingSimulation(seed: 4_242)
        simulation.runDays(30)

        let days = simulation.history.samples.map(\.day)
        #expect(days.count == 30)
        #expect(days == days.sorted())
        #expect(Set(days).count == days.count, "a day was recorded twice")
    }

    // MARK: - The numbers are the hive's

    /// The whole point of the record. If a sample and the snapshot taken at
    /// the same instant disagree, the charts are showing something that never
    /// happened.
    @Test("A sample matches the colony at the moment it was taken")
    func sampleMatchesTheHive() {
        var simulation = Fixture.thrivingSimulation(seed: 808)
        simulation.runDays(40)
        // One more tick lands exactly on a day boundary, so the sample and the
        // snapshot describe the same instant.
        _ = simulation.step()

        let snapshot = simulation.snapshot()
        guard let sample = simulation.history.samples.last else {
            Issue.record("no sample was taken")
            return
        }

        #expect(sample.day == snapshot.day)
        #expect(sample.season == snapshot.season)

        #expect(sample.adults == snapshot.population.adults)
        #expect(sample.brood == snapshot.population.brood)
        #expect(sample.workers == snapshot.population.workers)
        #expect(sample.drones == snapshot.population.drones)
        #expect(sample.winterBees == snapshot.population.winterBees)

        #expect(sample.edibleEnergy == snapshot.stores.edibleEnergy)
        #expect(sample.winterRequirement == snapshot.stores.winterRequirement)
        #expect(sample.winterReadiness == snapshot.stores.winterReadiness)

        #expect(sample.nestTemperature == snapshot.nest.temperatureCelsius)
        #expect(sample.outsideTemperature == snapshot.weather.temperatureCelsius)
        #expect(sample.combCells == snapshot.nest.builtCells)

        #expect(sample.nectarIntake == snapshot.dailyNectarIntake)
        #expect(sample.alarm == snapshot.alarm)
        #expect(sample.status == snapshot.status)

        // And the colony was actually alive for this, or none of the above
        // proved anything.
        #expect(sample.adults > 0)
        #expect(sample.population == sample.adults + sample.brood)
    }

    // MARK: - The cap

    @Test("The record keeps two years and drops the oldest day beyond it")
    func theCapHolds() {
        var history = ColonyHistory()
        for day in 0..<(ColonyHistory.limit + 50) {
            history.append(sample(onDay: day))
        }

        #expect(history.samples.count == ColonyHistory.limit)
        #expect(history.firstDay == 50)
        #expect(history.lastDay == ColonyHistory.limit + 49)
    }

    @Test("A day already in the record is not entered twice")
    func daysAreNotRepeated() {
        var history = ColonyHistory()
        history.append(sample(onDay: 7))
        history.append(sample(onDay: 7, adults: 999))
        history.append(sample(onDay: 6))

        #expect(history.samples.count == 1)
        #expect(history.samples.first?.adults == 100)
    }

    // MARK: - Reading it back

    @Test("The range picker asks for the days it says it does")
    func rangesSelectTheRightDays() {
        var history = ColonyHistory()
        // A year and a half, so "this year" and "all" differ.
        for day in 0..<(Season.daysPerYear + Season.daysPerSeason + 10) {
            history.append(sample(onDay: day))
        }
        let today = history.lastDay ?? 0

        #expect(history.samples(in: .all, endingOn: today).count == history.samples.count)
        #expect(history.samples(in: .month, endingOn: today).count == 30)

        // The newest day is the tenth of the second year's summer.
        let season = history.samples(in: .season, endingOn: today)
        #expect(season.count == 10)
        #expect(season.allSatisfy { $0.season == .summer })

        let year = history.samples(in: .year, endingOn: today)
        #expect(year.count == Season.daysPerSeason + 10)
        #expect(year.allSatisfy { $0.year == 2 })
    }

    @Test("Recent days are counted back from the newest sample, not the clock")
    func recentCountsBackFromTheRecord() {
        var history = ColonyHistory()
        for day in 100..<130 { history.append(sample(onDay: day)) }

        #expect(history.recent(7).map(\.day) == Array(123..<130))
        #expect(history.recent(500).count == 30)
        #expect(history.recent(0).isEmpty)
    }

    @Test("Seasons come back as bands, one per run of days")
    func seasonsBecomeBands() {
        var history = ColonyHistory()
        // The last ten days of spring and the first five of summer.
        for day in (Season.daysPerSeason - 10)..<(Season.daysPerSeason + 5) {
            history.append(sample(onDay: day))
        }

        let spans = SeasonSpan.spans(covering: history.samples)
        #expect(spans.map(\.season) == [.spring, .summer])
        #expect(spans[0].firstDay == Season.daysPerSeason - 10)
        #expect(spans[0].lastDay == Season.daysPerSeason - 1)
        #expect(spans[1].firstDay == Season.daysPerSeason)
        #expect(spans[1].lastDay == Season.daysPerSeason + 4)
        #expect(SeasonSpan.spans(covering: []).isEmpty)
    }

    // MARK: - Harmless to the colony

    /// The balance baseline was measured without the record. It must still
    /// reproduce with it, which means the record cannot draw from the random
    /// stream or change anything a system reads.
    @Test("Two identical colonies still advance identically with the record on")
    func identicalColoniesStayIdentical() {
        var a = Fixture.thrivingSimulation(seed: 99)
        var b = Fixture.thrivingSimulation(seed: 99)

        a.runDays(60)
        b.runDays(60)

        #expect(a == b, "identical seeds diverged")
        #expect(a.history.samples.count == 60, "the record was not being written")
    }

    @Test("The record takes nothing from the random stream and emits nothing")
    func historyDrawsNothing() {
        var simulation = Fixture.thrivingSimulation(seed: 31)
        simulation.runDays(3)
        var world = simulation.world

        var context = TickContext(
            clock: SimClock(epoch: epoch, tick: 4 * SimClock.ticksPerDay),
            config: .standard,
            rng: SeededRandom(seed: 12_345),
            ids: IDGenerator(startingAt: 500)
        )
        let stream = context.rng
        let ids = context.ids
        let hive = world.hive

        HistorySystem().update(&world, &context)

        #expect(context.rng == stream, "the record moved the random stream")
        #expect(context.ids == ids, "the record issued an identifier")
        #expect(context.events.isEmpty, "the record emitted an event")
        #expect(world.hive == hive, "the record changed the colony")
        #expect(world.history.lastDay == 4, "the record did not write anything")
    }

    /// The clock keeps running after a colony dies, and a record filled with
    /// identical empty days would push the colony's actual life out of it.
    @Test("A colony that has ended is recorded once and then left alone")
    func deadColoniesStopBeingRecorded() {
        var simulation = Fixture.thrivingSimulation(seed: 71)
        simulation.runDays(6)
        #expect(simulation.history.samples.count == 6)

        simulation.mutateWorld { $0.hive.bees = [] }
        simulation.runDays(1)

        let ended = simulation.history.samples.count
        #expect(ended == 7)
        #expect(simulation.history.samples.last?.status == .collapsed)
        #expect(simulation.history.samples.last?.adults == 0)

        simulation.runDays(20)
        #expect(simulation.history.samples.count == ended, "the record kept writing an empty nest")
    }

    @Test("Offline catch-up writes the same record live play would")
    func catchUpRecordsTheSameDays() {
        var live = Fixture.thrivingSimulation(seed: 5)
        var offline = Fixture.thrivingSimulation(seed: 5)

        live.runDays(21)
        offline.advance(to: .afterSimulated(days: 21))

        #expect(live.history == offline.history)
    }

    // MARK: - Old saves

    /// Every colony saved before the record existed has no `history` key, and
    /// `GameStore.load` treats an unreadable save as no save at all — so a
    /// decode failure here would silently delete people's colonies.
    @Test("A save written before the record existed still opens")
    func oldSavesStillDecode() throws {
        var simulation = Fixture.thrivingSimulation(seed: 61)
        simulation.runDays(4)

        let encoded = try JSONEncoder().encode(simulation.world)
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["history"] != nil, "the key is not there to remove")
        object.removeValue(forKey: "history")

        let withoutHistory = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(World.self, from: withoutHistory)

        #expect(decoded.history.isEmpty)
        // And the rest of the colony came through untouched.
        #expect(decoded.hive.bees.count == simulation.world.hive.bees.count)
        #expect(decoded.almanac == simulation.world.almanac)
    }

    @Test("A record that cannot be read costs the charts, not the colony")
    func unreadableRecordDoesNotLoseTheColony() throws {
        var simulation = Fixture.thrivingSimulation(seed: 62)
        simulation.runDays(4)

        let encoded = try JSONEncoder().encode(simulation.world)
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        // What a future field added to `DailySample` would look like to today's
        // decoder: samples that are no longer the shape it expects.
        object["history"] = ["samples": ["not a sample at all"]]

        let mangled = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(World.self, from: mangled)

        #expect(decoded.history.isEmpty)
        #expect(decoded.hive.bees.count == simulation.world.hive.bees.count)
    }

    @Test("The record survives a save and reload")
    func recordRoundTrips() throws {
        var simulation = Fixture.thrivingSimulation(seed: 63)
        simulation.runDays(9)

        let data = try JSONEncoder().encode(simulation)
        let restored = try JSONDecoder().decode(Simulation.self, from: data)

        #expect(restored.history == simulation.history)
        #expect(restored.history.samples.count == 9)
    }

    // MARK: - Helpers

    /// A sample with plausible numbers, for the tests that are about the
    /// record rather than about the colony.
    private func sample(onDay day: Int, adults: Int = 100) -> DailySample {
        DailySample(
            day: day,
            adults: adults,
            brood: 40,
            workers: adults - 1,
            drones: 1,
            winterBees: 0,
            edibleEnergy: 120,
            winterRequirement: 200,
            nestTemperature: 34,
            outsideTemperature: 18,
            combCells: 300,
            nectarIntake: 12,
            alarm: 0,
            status: .steady
        )
    }
}
