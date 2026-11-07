import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// What the Colony tab's tiles say.
///
/// The bands are the point. A dashboard that draws forty per cent of winter
/// stores in the same colour in April and in October is telling a player
/// nothing, and the same judgement written into a SwiftUI view could only be
/// checked by looking at a phone. These are the thresholds, stated, so that
/// moving one is a deliberate act with a failing test attached.
@Suite("Dashboard summary")
struct DashboardSummaryTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    /// A day in the record, with only the fields a given test cares about.
    private func sample(day: Int, adults: Int, brood: Int = 0) -> DailySample {
        DailySample(
            day: day,
            adults: adults,
            brood: brood,
            workers: adults,
            drones: 0,
            winterBees: 0,
            edibleEnergy: 100,
            winterRequirement: 200,
            nestTemperature: 35,
            outsideTemperature: 15,
            combCells: 4_000,
            nectarIntake: 5,
            alarm: 0,
            status: .steady
        )
    }

    private func history(_ populations: [Int]) -> ColonyHistory {
        var history = ColonyHistory()
        for (offset, adults) in populations.enumerated() {
            history.append(sample(day: offset, adults: adults))
        }
        return history
    }

    // MARK: - Stores

    @Test("A larder that is short means one thing in autumn and another in spring")
    func storesSeverityTurnsOnTheSeason() {
        // The same 40% of what the winter will cost.
        #expect(
            DashboardSummary.storesSeverity(
                readiness: 0.4, isWinterReady: false, season: .autumn
            ) == .alarm
        )
        #expect(
            DashboardSummary.storesSeverity(
                readiness: 0.4, isWinterReady: false, season: .spring
            ) == .notable,
            "there is a whole season of forage left to close the gap"
        )
    }

    @Test("A provisioned colony is calm whatever the month")
    func winterReadyIsAlwaysCalm() {
        for season in Season.allCases {
            #expect(
                DashboardSummary.storesSeverity(
                    readiness: 1, isWinterReady: true, season: season
                ) == .calm
            )
        }
    }

    @Test("An almost empty larder is a warning even in June")
    func anEmptyLarderIsAWarningInSummer() {
        #expect(
            DashboardSummary.storesSeverity(
                readiness: 0.05, isWinterReady: false, season: .summer
            ) == .caution
        )
    }

    @Test("Autumn is a warning until it is an alarm")
    func autumnBandsAtSixtyPerCent() {
        #expect(
            DashboardSummary.storesSeverity(
                readiness: 0.75, isWinterReady: false, season: .autumn
            ) == .caution
        )
        #expect(
            DashboardSummary.storesSeverity(
                readiness: 0.59, isWinterReady: false, season: .autumn
            ) == .alarm
        )
    }

    // MARK: - Trend

    @Test("A week of growth reads as rising, a week of loss as falling")
    func trendFollowsTheWeek() {
        #expect(DashboardSummary.populationTrend(history([100, 110, 120, 130])) == .rising)
        #expect(DashboardSummary.populationTrend(history([400, 380, 350, 300])) == .falling)
    }

    @Test("Ordinary day-to-day wobble is not a trend")
    func smallChangesAreSteady() {
        // Two per cent over the week, well inside the tolerance.
        #expect(DashboardSummary.populationTrend(history([1_000, 1_005, 1_010, 1_020])) == .steady)
    }

    @Test("A record with nothing in it, or one day in it, has no direction")
    func tooLittleRecordIsSteady() {
        #expect(DashboardSummary.populationTrend(ColonyHistory()) == .steady)
        #expect(DashboardSummary.populationTrend(history([500])) == .steady)
    }

    @Test("The trend looks back from the newest sample, not from the clock")
    func trendLooksBackFromTheRecord() {
        // Ten days recorded; the last seven of them are flat, and only the
        // first three fell. A window counted from the clock would find the
        // fall; one counted from the record should not.
        let record = history([900, 700, 500, 500, 500, 500, 500, 500, 500, 500])
        #expect(DashboardSummary.populationTrend(record, overDays: 7) == .steady)
        #expect(DashboardSummary.populationTrend(record, overDays: 10) == .falling)
    }

    // MARK: - Population

    @Test("A colony shrinking in May is a worry and one shrinking in October is not")
    func shrinkingIsSeasonal() {
        #expect(
            DashboardSummary.populationSeverity(
                vitality: 0.9, trend: .falling, season: .spring
            ) == .caution
        )
        #expect(
            DashboardSummary.populationSeverity(
                vitality: 0.9, trend: .falling, season: .autumn
            ) == .calm,
            "the summer bees die and are not replaced; that is what autumn is"
        )
    }

    @Test("Condition outranks direction")
    func poorConditionIsAnAlarmHowever_ItIsTrending() {
        #expect(
            DashboardSummary.populationSeverity(
                vitality: 0.4, trend: .rising, season: .summer
            ) == .alarm
        )
        #expect(
            DashboardSummary.populationSeverity(
                vitality: 0.65, trend: .rising, season: .summer
            ) == .caution
        )
    }

    // MARK: - Queen

    @Test("Every queen state that ends the colony is drawn as an alarm")
    func queenStatesThatEndTheColony() {
        #expect(DashboardSummary.queenSeverity(.laying) == .calm)
        #expect(DashboardSummary.queenSeverity(.virgin) == .notable)
        #expect(DashboardSummary.queenSeverity(.absent) == .alarm)
        #expect(DashboardSummary.queenSeverity(.droneLayer) == .alarm)
        #expect(DashboardSummary.queenSeverity(.layingWorkers) == .alarm)
    }

    // MARK: - Nest

    @Test("A cold nest only matters while there is brood in it")
    func temperatureOnlyMattersWithBrood() {
        #expect(
            DashboardSummary.nestSeverity(
                temperatureCelsius: 24, hasBrood: true, combOccupancy: 0.5
            ) == .alarm
        )
        #expect(
            DashboardSummary.nestSeverity(
                temperatureCelsius: 24, hasBrood: false, combOccupancy: 0.5
            ) == .calm,
            "a broodless winter cluster runs cold on purpose"
        )
    }

    @Test("A full nest is the swarm question arriving early")
    func fullCombIsRaisedOnItsOwn() {
        #expect(
            DashboardSummary.nestSeverity(
                temperatureCelsius: 35, hasBrood: true, combOccupancy: 0.92
            ) == .notable
        )
        #expect(
            DashboardSummary.nestSeverity(
                temperatureCelsius: 35, hasBrood: true, combOccupancy: 0.97
            ) == .caution
        )
    }

    @Test("The worse of the two worries is the one the tile shows")
    func nestTakesTheWorseOfTheTwo() {
        #expect(
            DashboardSummary.nestSeverity(
                temperatureCelsius: 30, hasBrood: true, combOccupancy: 0.97
            ) == .alarm,
            "five degrees off target outranks a full comb"
        )
    }

    // MARK: - Forage

    @Test("Nothing to work is an alarm, except in winter")
    func nothingInBloom() {
        #expect(DashboardSummary.forageSeverity(inBloom: 0, season: .summer) == .alarm)
        #expect(DashboardSummary.forageSeverity(inBloom: 0, season: .winter) == .notable)
        #expect(DashboardSummary.forageSeverity(inBloom: 2, season: .spring) == .caution)
        #expect(DashboardSummary.forageSeverity(inBloom: 6, season: .spring) == .calm)
    }

    // MARK: - Health

    @Test("The infection bands are the ones the engine already warns at")
    func healthBands() {
        #expect(DashboardSummary.healthSeverity(dominantLevel: 0.1) == .notable)
        #expect(DashboardSummary.healthSeverity(dominantLevel: 0.3) == .caution)
        #expect(DashboardSummary.healthSeverity(dominantLevel: 0.7) == .alarm)
    }

    // MARK: - Attention

    @Test("One thing needing attention is not one things")
    func attentionReadsAsEnglish() {
        #expect(DashboardSummary.summary(forAlertCount: 0) == "Nothing needs attention.")
        #expect(DashboardSummary.summary(forAlertCount: 1) == "One thing needs attention.")
        #expect(DashboardSummary.summary(forAlertCount: 4) == "4 things need attention.")
    }

    @Test("The row takes the colour of the worst alert under it")
    func attentionTakesTheWorstSeverity() {
        let alerts = [
            ColonyAlert(kind: .crowded, severity: .notable, title: "Nest Is Full", detail: ""),
            ColonyAlert(kind: .starving, severity: .critical, title: "Starving", detail: ""),
            ColonyAlert(kind: .tooCold, severity: .warning, title: "Cold", detail: "")
        ]
        let attention = DashboardSummary.attention(for: alerts)
        #expect(attention.count == 3)
        #expect(attention.severity == .alarm)
        #expect(!attention.isEmpty)
    }

    @Test("A colony with nothing wrong has an empty attention row")
    func noAlertsIsEmpty() {
        let attention = DashboardSummary.attention(for: [])
        #expect(attention.isEmpty)
        #expect(attention.severity == .calm)
    }

    // MARK: - The whole overview

    /// The tiles are what the grid draws, so their number, order and
    /// completeness are load-bearing: a view that is handed seven tiles draws
    /// seven boxes and asks no questions.
    @Test("A live colony produces a tile for everything the overview shows")
    @MainActor
    func aRealColonyFillsTheGrid() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 21
        )
        let store = GameStore(
            simulation: simulation,
            persistence: InMemoryPersistence(),
            clock: { self.epoch.addingTimeInterval(40 * 24 * 300) }
        )
        store.catchUp()

        let summary = DashboardSummary(snapshot: store.snapshot, history: store.history)

        // Health is the only conditional one.
        let expected: [DashboardSummary.Tile.Kind] =
            [.stores, .population, .queen, .nest, .honey, .forage, .record]
        let drawn = summary.tiles.map(\.kind)
        for kind in expected {
            #expect(drawn.contains(kind), "no \(kind.rawValue) tile")
        }
        #expect(drawn == drawn.sorted { lhs, rhs in
            let order = DashboardSummary.Tile.Kind.allCases
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }, "the tiles came out in an order the grid did not ask for")

        // Every tile has something to say, and nothing to say it with is a bug
        // the view cannot recover from.
        for tile in summary.tiles {
            #expect(!tile.headline.isEmpty, "\(tile.kind.rawValue) has no number")
            #expect(!tile.caption.isEmpty, "\(tile.kind.rawValue) has no caption")
            #expect(!tile.spoken.isEmpty, "\(tile.kind.rawValue) says nothing to VoiceOver")
            #expect(!tile.title.isEmpty)
            #expect(!tile.symbolName.isEmpty)
            if let gauge = tile.gauge {
                #expect(gauge >= 0 && gauge <= 1, "\(tile.kind.rawValue) gauge is off the bar")
            }
        }

        #expect(summary.tile(.stores) != nil)
        #expect(summary.attention.count == store.snapshot.alerts.count)
    }

    @Test("A clean colony is shown no health tile")
    @MainActor
    func healthTileOnlyAppearsWhenThereIsSomething() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 21
        )
        let store = GameStore(
            simulation: simulation,
            persistence: InMemoryPersistence(),
            clock: { self.epoch }
        )

        let snapshot = store.snapshot
        let summary = DashboardSummary(snapshot: snapshot, history: store.history)

        let hasSomething = !snapshot.health.infections.isEmpty
            || !snapshot.health.recentAttacks.isEmpty
        #expect((summary.tile(.health) != nil) == hasSomething)
    }
}
