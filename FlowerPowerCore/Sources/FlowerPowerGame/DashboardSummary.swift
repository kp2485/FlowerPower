//
//  DashboardSummary.swift
//  FlowerPowerGame
//
//  What the Colony tab's tiles say, and how worried each of them should look.
//
//  The dashboard used to be a column of full-size cards, and every one of them
//  worked out its own judgement inline: this meter is amber above ninety per
//  cent, that one is red below sixty, a falling population is alarming unless
//  it is October. Written into a SwiftUI view none of it could be tested, and
//  none of it could be checked against the same judgement made somewhere else —
//  the watch, a widget, the notification the engine already sends about the
//  same thing.
//
//  So the tiles are computed here. A tile is a symbol, one number, a caption
//  and a severity, and the view's whole job is to draw those four things in a
//  box. The bands are stated once, in public functions, because a threshold
//  nobody can point at is a threshold that drifts.
//
//  Nothing here decides anything about the colony. It only decides what to say
//  about it.
//

import Foundation
import FlowerPowerCore

public struct DashboardSummary: Equatable, Sendable {

    // MARK: - How worried a tile looks

    /// Four bands rather than a colour, because a colour is SwiftUI and the
    /// watch draws the same judgement in a different palette.
    ///
    /// Deliberately not `SimEvent.Severity`: that one is about events worth
    /// recording and has a `routine` case that means "happened, and is fine",
    /// which is not the same as a tile that is calm. They map onto each other
    /// through `init(_:)` below where an alert has to be shown as a tile.
    public enum Severity: Int, Codable, Comparable, Sendable, CaseIterable {
        case calm
        case notable
        case caution
        case alarm

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public init(_ severity: SimEvent.Severity) {
            switch severity {
            case .routine: self = .calm
            case .notable: self = .notable
            case .warning: self = .caution
            case .critical: self = .alarm
            }
        }
    }

    // MARK: - Which way a number is going

    /// An arrow, from two readings a week apart.
    ///
    /// A single number on a tile says nothing about whether the colony is
    /// coming or going, which is most of what somebody glancing at it wants.
    /// The tolerance is five per cent: a colony that loses two hundred bees out
    /// of twenty thousand overnight has not started declining, it has had a
    /// Tuesday.
    public enum Trend: String, Codable, Sendable, CaseIterable {
        case rising
        case steady
        case falling

        public var symbolName: String {
            switch self {
            case .rising: return "arrow.up.right"
            case .steady: return "arrow.right"
            case .falling: return "arrow.down.right"
            }
        }

        public var displayName: String {
            switch self {
            case .rising: return "rising"
            case .steady: return "steady"
            case .falling: return "falling"
            }
        }

        /// The change from `earlier` to `later`, as a proportion of `earlier`.
        ///
        /// A colony that had nothing and now has something is rising, which is
        /// the only sensible reading of a division by zero here.
        public static func between(
            _ earlier: Double,
            _ later: Double,
            tolerance: Double = 0.05
        ) -> Trend {
            guard earlier > 0 else { return later > 0 ? .rising : .steady }
            let change = (later - earlier) / earlier
            if change > tolerance { return .rising }
            if change < -tolerance { return .falling }
            return .steady
        }
    }

    // MARK: - A tile

    public struct Tile: Identifiable, Equatable, Sendable {

        /// The eight things the overview shows, and the order it shows them
        /// in. `CaseIterable` is the order: stores first because a colony dies
        /// of an empty larder before it dies of anything else, and the record
        /// last because it is the only one that is not about today.
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case stores
            case population
            case queen
            case nest
            case health
            case honey
            case forage
            case record

            public var title: String {
                switch self {
                case .stores: return "Stores"
                case .population: return "Population"
                case .queen: return "Queen"
                case .nest: return "Nest"
                case .health: return "Health"
                case .honey: return "Honey"
                case .forage: return "Forage"
                case .record: return "Record"
                }
            }

            public var symbolName: String {
                switch self {
                case .stores: return "archivebox.fill"
                case .population: return "person.3.fill"
                case .queen: return "crown.fill"
                case .nest: return "house.fill"
                case .health: return "cross.case.fill"
                case .honey: return "drop.fill"
                case .forage: return "leaf.fill"
                case .record: return "book.closed.fill"
                }
            }
        }

        public let kind: Kind
        /// The one number, already formatted. A tile has room for about four
        /// characters and no room at all for a second line of digits.
        public let headline: String
        /// What the number is, in a handful of words.
        public let caption: String
        public let severity: Severity
        /// 0...1 where a bar means something, nil where it does not. Queen age
        /// has no ceiling and honey to spare has no scale.
        public let gauge: Double?
        public let trend: Trend?
        /// What VoiceOver reads after the title, as a sentence rather than a
        /// pile of digits: "82 percent of what winter needs".
        public let spoken: String

        public init(
            kind: Kind,
            headline: String,
            caption: String,
            severity: Severity,
            gauge: Double? = nil,
            trend: Trend? = nil,
            spoken: String
        ) {
            self.kind = kind
            self.headline = headline
            self.caption = caption
            self.severity = severity
            self.gauge = gauge
            self.trend = trend
            self.spoken = spoken
        }

        public var id: Kind { kind }
        public var title: String { kind.title }
        public var symbolName: String { kind.symbolName }
    }

    // MARK: - The things that need attention

    /// The alerts, collapsed to one line.
    ///
    /// Six full-size alert cards is the state a dashboard reaches exactly when
    /// the player has least appetite for reading six of anything. One row that
    /// says how many and how bad the worst of them is, and the list behind it.
    public struct Attention: Equatable, Sendable {

        public let count: Int
        public let severity: Severity
        /// "Three things need attention."
        public let summary: String

        public init(count: Int, severity: Severity, summary: String) {
            self.count = count
            self.severity = severity
            self.summary = summary
        }

        public var isEmpty: Bool { count == 0 }
    }

    public let tiles: [Tile]
    public let attention: Attention

    // MARK: - Building it

    public init(snapshot: ColonySnapshot, history: ColonyHistory) {
        self.tiles = Self.tiles(for: snapshot, history: history)
        self.attention = Self.attention(for: snapshot.alerts)
    }

    public func tile(_ kind: Tile.Kind) -> Tile? {
        tiles.first { $0.kind == kind }
    }
}

// MARK: - The tiles

extension DashboardSummary {

    static func tiles(for snapshot: ColonySnapshot, history: ColonyHistory) -> [Tile] {
        var tiles: [Tile] = []
        tiles.append(storesTile(snapshot))
        tiles.append(populationTile(snapshot, history: history))
        tiles.append(queenTile(snapshot))
        tiles.append(nestTile(snapshot))
        // Only when there is something. A "Health: 0%" tile on a clean colony
        // is a quarter of the overview spent saying nothing.
        if let health = healthTile(snapshot) { tiles.append(health) }
        tiles.append(honeyTile(snapshot))
        tiles.append(forageTile(snapshot))
        tiles.append(recordTile(snapshot))
        return tiles
    }

    // MARK: Stores

    static func storesTile(_ snapshot: ColonySnapshot) -> Tile {
        let stores = snapshot.stores
        let percent = Int((stores.winterReadiness * 100).rounded())

        return Tile(
            kind: .stores,
            headline: "\(percent)%",
            caption: "of what winter needs",
            severity: storesSeverity(
                readiness: stores.winterReadiness,
                isWinterReady: stores.isWinterReady,
                season: snapshot.season
            ),
            gauge: stores.winterReadiness,
            spoken: "\(percent) percent of what winter needs, "
                + "\(Int(stores.edibleEnergy.rounded())) units of "
                + "\(Int(stores.winterRequirement.rounded()))"
        )
    }

    /// How alarming a given readiness is, which depends entirely on the month.
    ///
    /// Forty per cent in April is a colony that has eaten its winter and is
    /// about to start earning; forty per cent in October is a colony that will
    /// be dead in February. The same number, and nothing about it says which
    /// one it is.
    public static func storesSeverity(
        readiness: Double,
        isWinterReady: Bool,
        season: Season
    ) -> Severity {
        if isWinterReady { return .calm }
        switch season {
        case .autumn, .winter:
            // The provisioning is over or nearly so, and the gap is now the
            // whole question.
            if readiness < 0.6 { return .alarm }
            return .caution
        case .spring, .summer:
            // There is a season of forage left to close it in. Worth a mark
            // rather than a warning — except for a larder that is genuinely
            // nearly empty, which is starvation whatever the date.
            if readiness < 0.15 { return .caution }
            return .notable
        }
    }

    // MARK: Population

    static func populationTile(_ snapshot: ColonySnapshot, history: ColonyHistory) -> Tile {
        let population = snapshot.population
        let trend = populationTrend(history)

        return Tile(
            kind: .population,
            headline: "\(population.total)",
            caption: "\(population.adults) adults, \(population.brood) brood",
            severity: populationSeverity(
                vitality: population.averageVitality,
                trend: trend,
                season: snapshot.season
            ),
            gauge: population.averageVitality,
            trend: trend,
            spoken: "\(population.total) bees and brood, \(trend.displayName). "
                + "\(population.adults) adults, \(population.brood) brood"
        )
    }

    /// Which way the colony is going, over the last week of the record.
    ///
    /// A week rather than a day: brood emerges in batches and a population read
    /// day to day is mostly noise. Seven days back from the newest sample
    /// rather than from the clock, so a colony nobody has opened for a fortnight
    /// still shows the week it actually lived.
    public static func populationTrend(_ history: ColonyHistory, overDays days: Int = 7) -> Trend {
        let recent = history.recent(days)
        guard let first = recent.first, let last = recent.last, first.day != last.day else {
            return .steady
        }
        return Trend.between(Double(first.population), Double(last.population))
    }

    /// Condition first, direction second.
    ///
    /// A shrinking colony in autumn is a colony doing autumn: the summer bees
    /// die and are not replaced, and drawing that in amber every September
    /// would teach the player to ignore the colour. A shrinking colony in May
    /// is something wrong.
    public static func populationSeverity(
        vitality: Double,
        trend: Trend,
        season: Season
    ) -> Severity {
        if vitality < 0.5 { return .alarm }
        if vitality < 0.7 { return .caution }
        if trend == .falling, season == .spring || season == .summer { return .caution }
        return .calm
    }

    // MARK: Queen

    static func queenTile(_ snapshot: ColonySnapshot) -> Tile {
        let queen = snapshot.queen
        let caption: String
        switch queen.state {
        case .absent, .layingWorkers:
            caption = queen.daysQueenless == 1
                ? "queenless a day"
                : "queenless \(queen.daysQueenless) days"
        default:
            caption = queen.ageDays == 1 ? "a day old" : "\(queen.ageDays) days old"
        }

        // Diversity is the number that matters about a queen who is laying, and
        // meaningless about one who is not there.
        let gauge: Double? = (queen.state == .laying || queen.state == .droneLayer)
            ? queen.geneticDiversity
            : nil

        return Tile(
            kind: .queen,
            headline: queen.state.displayName,
            caption: caption,
            severity: queenSeverity(queen.state),
            gauge: gauge,
            spoken: "\(queen.state.displayName), \(caption)"
        )
    }

    /// Three of the five queen states are the end of the colony unless
    /// something happens, and the tile says so.
    public static func queenSeverity(_ state: QueenSummary.State) -> Severity {
        switch state {
        case .laying: return .calm
        // She may yet fly and mate. Worth seeing; not worth alarm.
        case .virgin: return .notable
        case .absent, .droneLayer, .layingWorkers: return .alarm
        }
    }

    // MARK: Nest

    static func nestTile(_ snapshot: ColonySnapshot) -> Tile {
        let nest = snapshot.nest
        let degrees = Int(nest.temperatureCelsius.rounded())
        let occupancy = Int((nest.combOccupancy * 100).rounded())

        return Tile(
            kind: .nest,
            headline: "\(degrees)°C",
            caption: "\(occupancy)% of the comb in use",
            severity: nestSeverity(
                temperatureCelsius: nest.temperatureCelsius,
                hasBrood: snapshot.population.brood > 0,
                combOccupancy: nest.combOccupancy
            ),
            gauge: nest.combOccupancy,
            spoken: "\(degrees) degrees in the brood nest, "
                + "\(occupancy) percent of the comb in use, "
                + "\(nest.freeCells) cells free"
        )
    }

    /// Two quite different worries under one tile: the temperature, and the
    /// room.
    ///
    /// The temperature only means anything while there is brood to keep warm —
    /// a winter cluster with no brood runs far below thirty-five on purpose and
    /// drawing that in red every January would be a lie. The room is the
    /// swarming question arriving a fortnight early.
    public static func nestSeverity(
        temperatureCelsius: Double,
        hasBrood: Bool,
        combOccupancy: Double,
        target: Double = 35
    ) -> Severity {
        var severity = Severity.calm

        if hasBrood {
            let deviation = abs(temperatureCelsius - target)
            if deviation > 4 {
                severity = .alarm
            } else if deviation > 2 {
                severity = .caution
            }
        }

        if combOccupancy > 0.95 {
            severity = max(severity, .caution)
        } else if combOccupancy > 0.9 {
            severity = max(severity, .notable)
        }

        return severity
    }

    // MARK: Health

    static func healthTile(_ snapshot: ColonySnapshot) -> Tile? {
        let health = snapshot.health
        guard !health.infections.isEmpty || !health.recentAttacks.isEmpty else { return nil }

        // The worst infection is the headline where there is one. Where there
        // is not, the tile exists because something has been at the entrance.
        if let dominant = health.dominantInfection,
           let level = health.infections[dominant] {
            let percent = Int((level * 100).rounded())
            return Tile(
                kind: .health,
                headline: "\(percent)%",
                caption: dominant.displayName,
                severity: healthSeverity(dominantLevel: level),
                gauge: min(1, max(0, health.totalPressure)),
                spoken: "\(dominant.displayName) at \(percent) percent"
            )
        }

        let raids = health.recentAttacks.count
        return Tile(
            kind: .health,
            headline: "\(raids)",
            caption: raids == 1 ? "raid this fortnight" : "raids this fortnight",
            severity: raids >= 2 ? .caution : .notable,
            spoken: "\(raids) \(raids == 1 ? "raid" : "raids") in the past fortnight"
        )
    }

    /// The same quarter and half the engine uses for the disease alert, so the
    /// tile and the alert never disagree about how bad a mite load is.
    public static func healthSeverity(dominantLevel: Double) -> Severity {
        if dominantLevel > 0.5 { return .alarm }
        if dominantLevel > 0.25 { return .caution }
        return .notable
    }

    // MARK: Honey

    static func honeyTile(_ snapshot: ColonySnapshot) -> Tile {
        let spare = Int(snapshot.harvestableHoney.rounded())
        let banked = Int(snapshot.honeyTaken.rounded())

        return Tile(
            kind: .honey,
            headline: "\(spare)",
            caption: banked >= 1 ? "to spare, \(banked) banked" : "units to spare",
            // The one tile that is never a worry: there is nothing wrong with
            // having no surplus, and a colony holding one is doing well.
            severity: spare >= 1 ? .notable : .calm,
            spoken: banked >= 1
                ? "\(spare) units to spare, \(banked) already banked"
                : "\(spare) units to spare"
        )
    }

    // MARK: Forage

    static func forageTile(_ snapshot: ColonySnapshot) -> Tile {
        let garden = snapshot.patches.filter(\.isInBloom).count
        let wild = snapshot.wildPatches.filter(\.isInBloom).count
        let total = garden + wild

        return Tile(
            kind: .forage,
            headline: "\(total)",
            caption: wild > 0 ? "in bloom, \(wild) of them wild" : "patches in bloom",
            severity: forageSeverity(inBloom: total, season: snapshot.season),
            spoken: total == 1
                ? "one patch in bloom"
                : "\(total) patches in bloom, \(garden) of them yours"
        )
    }

    /// Nothing to work is the game's one real emergency that the player can fix
    /// by standing up, and it is worth the loudest colour the tile has — except
    /// in winter, when two plants flower in the whole country and an empty
    /// count is simply January.
    public static func forageSeverity(inBloom: Int, season: Season) -> Severity {
        if season == .winter { return inBloom == 0 ? .notable : .calm }
        if inBloom == 0 { return .alarm }
        if inBloom <= 2 { return .caution }
        return .calm
    }

    // MARK: Record

    static func recordTile(_ snapshot: ColonySnapshot) -> Tile {
        let queens = snapshot.lineage.count

        return Tile(
            kind: .record,
            headline: "Year \(snapshot.year)",
            caption: queens == 1 ? "one queen so far" : "\(queens) queens so far",
            severity: .calm,
            spoken: "Year \(snapshot.year), "
                + (queens == 1 ? "one queen so far" : "\(queens) queens so far")
        )
    }

    // MARK: Attention

    static func attention(for alerts: [ColonyAlert]) -> Attention {
        let worst = alerts.map { Severity($0.severity) }.max() ?? .calm
        return Attention(
            count: alerts.count,
            severity: worst,
            summary: summary(forAlertCount: alerts.count)
        )
    }

    /// Written out rather than "\(n) things", because "1 things need attention"
    /// is the kind of sentence that makes a player stop believing the rest of
    /// the screen.
    public static func summary(forAlertCount count: Int) -> String {
        switch count {
        case 0: return "Nothing needs attention."
        case 1: return "One thing needs attention."
        default: return "\(count) things need attention."
        }
    }
}
