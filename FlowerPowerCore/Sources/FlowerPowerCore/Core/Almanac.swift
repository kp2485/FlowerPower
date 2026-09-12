//
//  Almanac.swift
//  FlowerPowerCore
//
//  The colony's year, written by the game.
//
//  One line a day at most, and only when something happened. The first flow,
//  the first swarm cell, the day the honey peaked, a raid, a queen coming home
//  mated, what ended it all. Nothing routine: births and deaths happen every
//  day and are not news.
//
//  This is what winter is for. There is nothing to photograph and little to
//  watch, and a colony that has been through a year has a year to read.
//

import Foundation

public struct AlmanacEntry: Codable, Equatable, Identifiable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case season, forage, queen, swarm, threat, disease, stores, harvest, colony
    }

    public let day: Int
    public let season: Season
    public let kind: Kind
    public let text: String

    public init(day: Int, season: Season, kind: Kind, text: String) {
        self.day = day
        self.season = season
        self.kind = kind
        self.text = text
    }

    public var id: String { "\(day)-\(kind.rawValue)-\(text.hashValue)" }
    public var year: Int { day / Season.daysPerYear + 1 }
    public var dayOfYear: Int { day % Season.daysPerYear + 1 }
}

/// What a colony did in one year of its life, counted rather than described.
///
/// The almanac is prose, and prose is a poor thing to count: "the first swarm
/// cells are started", "a swarm leaves with 240 bees" and "the swarm is called
/// off" are all `.swarm` entries and mean quite different things. So the
/// numbers are tallied as the lines are written, from the events themselves.
public struct YearTally: Codable, Equatable, Sendable, Identifiable {

    public let year: Int

    public var swarms = 0
    public var splits = 0
    public var queensRaised = 0
    public var queensMated = 0
    public var raids = 0
    public var raidsRepelled = 0
    public var infections = 0
    public var honeyTaken = 0.0
    public var peakHoney = 0.0
    public var combAdded = 0

    public var id: Int { year }

    public init(year: Int) {
        self.year = year
    }

    public var isEmpty: Bool {
        swarms == 0 && splits == 0 && queensRaised == 0 && raids == 0
            && infections == 0 && honeyTaken == 0 && peakHoney == 0 && combAdded == 0
    }
}

public struct Almanac: Codable, Equatable, Sendable {

    public private(set) var entries: [AlmanacEntry]

    /// Enough for a couple of years of a busy colony. Older lines go.
    public static let limit = 400

    /// Honey high-water mark, so "the honey peaked" is written once when it is
    /// true rather than every day it climbs.
    public private(set) var peakHoney: Double

    /// One per year the colony has lived, oldest first.
    ///
    /// An array rather than a dictionary keyed by year, deliberately: a
    /// `Dictionary` encodes its pairs in hash order, which differs between
    /// processes, and a save file that differs run to run is a nuisance to
    /// diff and a trap for anyone comparing two of them. See
    /// `PathogenLoad.ordered` for the version of this that mattered.
    public private(set) var tallies: [YearTally]

    public init(
        entries: [AlmanacEntry] = [],
        peakHoney: Double = 0,
        tallies: [YearTally] = []
    ) {
        self.entries = entries
        self.peakHoney = peakHoney
        self.tallies = tallies
    }

    /// Saves written before the tallies existed decode without them, rather
    /// than failing to decode at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([AlmanacEntry].self, forKey: .entries) ?? []
        peakHoney = try container.decodeIfPresent(Double.self, forKey: .peakHoney) ?? 0
        tallies = try container.decodeIfPresent([YearTally].self, forKey: .tallies) ?? []
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entries(inYear year: Int) -> [AlmanacEntry] {
        entries.filter { $0.year == year }
    }

    public func tally(forYear year: Int) -> YearTally? {
        tallies.first { $0.year == year }
    }

    /// The years the colony has a record of, oldest first.
    public var years: [Int] {
        tallies.map(\.year)
    }

    /// Adds to the running count for a year, creating it the first time.
    private mutating func tallying(_ year: Int, _ body: (inout YearTally) -> Void) {
        if let index = tallies.firstIndex(where: { $0.year == year }) {
            body(&tallies[index])
        } else {
            var fresh = YearTally(year: year)
            body(&fresh)
            // Kept in order, so `years` and the review read chronologically
            // however the colony was played.
            let at = tallies.firstIndex { $0.year > year } ?? tallies.endIndex
            tallies.insert(fresh, at: at)
        }
    }

    public var latestYear: Int { entries.last?.year ?? 1 }

    // MARK: - Writing

    mutating func write(_ kind: AlmanacEntry.Kind, _ text: String, day: Int) {
        let season = Season(day: day)
        // One line per kind per day. A wasp siege produces several attack
        // events across the day; the almanac says it once.
        if entries.last(where: { $0.day == day && $0.kind == kind && $0.text == text }) != nil {
            return
        }
        entries.append(AlmanacEntry(day: day, season: season, kind: kind, text: text))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }

    /// Turns a day's events into lines. Called once per tick with that tick's
    /// events; the per-kind dedupe above makes that safe.
    public mutating func chronicle(
        _ events: [SimEvent],
        day: Int,
        honey: Double,
        lineage: Lineage
    ) {
        // Season turning is not an event, it is a date. Written on the first
        // day of each season.
        if day % Season.daysPerSeason == 0 {
            let season = Season(day: day)
            write(.season, "\(season.rawValue.capitalized) begins.", day: day)
        }

        // The honey peak is worth exactly one line, on the day it is set.
        if honey > peakHoney {
            let wasMeaningful = peakHoney > 0 && honey > peakHoney * 1.05
            peakHoney = honey
            if wasMeaningful, Season(day: day) != .winter {
                write(.stores, "Stores reach a new high of \(Int(honey.rounded())) units.", day: day)
            }
        }

        let queen = lineage.reigning?.title ?? "The queen"
        let year = day / Season.daysPerYear + 1

        tallying(year) { $0.peakHoney = max($0.peakHoney, honey) }

        for event in events {
            // Counted from the events rather than read back out of the prose.
            switch event {
            case .swarmed: tallying(year) { $0.swarms += 1 }
            case .colonyDivided: tallying(year) { $0.splits += 1 }
            case .queenEmerged: tallying(year) { $0.queensRaised += 1 }
            case .queenMated: tallying(year) { $0.queensMated += 1 }
            case .attacked: tallying(year) { $0.raids += 1 }
            case .attackRepelled: tallying(year) { $0.raidsRepelled += 1 }
            case .infectionDetected: tallying(year) { $0.infections += 1 }
            case .honeyTaken(let units): tallying(year) { $0.honeyTaken += units }
            case .combAdded(let cells): tallying(year) { $0.combAdded += cells }
            default: break
            }
        }

        for event in events {
            switch event {
            case .nectarFlowBegan:
                write(.forage, "The nectar begins to flow.", day: day)
            case .dearth:
                write(.forage, "A dearth. Little is coming in.", day: day)
            case .queenCellStarted(let purpose):
                switch purpose {
                case .swarm: write(.swarm, "The first swarm cells are started.", day: day)
                case .supersedure: write(.queen, "The bees begin raising a successor to \(queen).", day: day)
                case .emergency: write(.queen, "Queenless, the colony raises an emergency queen.", day: day)
                }
            case .queenEmerged:
                write(.queen, "A new queen emerges.", day: day)
            case .queenMated(let patrilines):
                write(.queen, "\(queen) returns from her mating flight, mated with \(patrilines) drones.", day: day)
            case .matingFlightFailed:
                write(.queen, "The virgin queen does not return from her mating flight.", day: day)
            case .queenLost:
                write(.queen, "\(queen) is lost.", day: day)
            case .supersededQueen:
                write(.queen, "\(queen) is superseded.", day: day)
            case .swarmed(let lost):
                write(.swarm, "A swarm leaves with \(lost) bees and the old queen.", day: day)
            case .swarmPreparing(let departs):
                write(.swarm, "Swarm cells are capped; the colony will divide in about \(max(1, departs - day)) days.", day: day)
            case .swarmAbandoned:
                write(.swarm, "The swarm is called off. The bees tear down their queen cells.", day: day)
            case .combAdded(let cells):
                write(.colony, "The nest is opened up: room for \(cells) more cells.", day: day)
            case .colonyDivided(let left):
                write(.swarm, "The colony is divided on purpose. \(left) bees leave with \(queen); "
                      + "the flying bees stay.", day: day)
            case .absconded(let lost):
                write(.colony, "The colony absconds, \(lost) bees abandoning the nest.", day: day)
            case .layingWorkersAppeared:
                write(.queen, "Laying workers appear. There is no way back from this.", day: day)
            case .colonyCollapsed:
                write(.colony, "The colony is gone.", day: day)
            case .threatBegan(let predator, _):
                write(.threat, "\(predator.displayName) at the nest.", day: day)
            case .attackRepelled(let predator):
                write(.threat, "The \(predator.displayName.lowercased()) is driven off.", day: day)
            case .raidSucceeded(let predator, let stores):
                write(.threat, "\(predator.displayName) get in and take \(Int(stores.rounded())) units of stores.", day: day)
            case .combLost(let count):
                write(.threat, "\(count) cells of comb are destroyed.", day: day)
            case .infectionDetected(let pathogen):
                write(.disease, "\(pathogen.displayName) is found in the colony.", day: day)
            case .infectionCritical(let pathogen):
                write(.disease, "\(pathogen.displayName) reaches a dangerous level.", day: day)
            case .infectionCleared(let pathogen):
                write(.disease, "The colony clears \(pathogen.displayName.lowercased()).", day: day)
            case .winterStoresLow(let have, let need):
                write(.stores, "Winter stores are short: \(Int(have)) of \(Int(need)) needed.", day: day)
            case .entranceSealed(let sealed):
                write(.colony, sealed
                      ? "The bees seal the entrance with propolis for winter."
                      : "The entrance is left open through the winter.", day: day)
            case .honeyTaken(let units):
                write(.harvest, "\(Int(units.rounded())) units of honey are taken.", day: day)
            case .fed(let units):
                // Deliberately not deducted from the year's `honeyTaken`
                // tally. What the player took in a given year is a fact about
                // that year; the bank it came out of is not annual, and a
                // colony fed in January out of last autumn's crop would
                // otherwise show a harvest it never had. The line says it
                // instead — which is what the almanac is for.
                write(.harvest,
                      "\(Int(units.rounded())) units of honey are given back to the bees.",
                      day: day)
            case .postureAdopted(let posture):
                if posture != .instinct {
                    write(.colony, "\(posture.displayName).", day: day)
                }
            case .milestone(let milestone):
                // A line per milestone, and the dedupe in `write` is keyed on
                // the text, so two badges earned on the same day both get
                // written rather than the second being swallowed as a repeat.
                write(.colony, "A first for the colony: \(milestone.title.lowercased()).",
                      day: day)
            default:
                break
            }
        }
    }
}

// MARK: - The year, read back

/// An account of a year the colony has finished, for reading in winter.
///
/// Winter is a quarter of the game with nothing to photograph and, until now,
/// nothing to look at either — the pacing note in `SimClock` argues the answer
/// is something to *do* in winter rather than a faster clock, and this is the
/// first half of that: something to read. It is the part of the game that is
/// about the colony having a history rather than a state.
public struct YearInReview: Equatable, Sendable {

    public let year: Int
    public let tally: YearTally
    /// The year's lines, in order, so the interface can show the whole thing
    /// under the summary.
    public let entries: [AlmanacEntry]
    /// The queens who reigned at any point during the year.
    public let queens: [QueenRecord]

    /// One line for the top of the page.
    public let headline: String
    /// A handful of sentences under it. Only what is true — a quiet year gets
    /// a short review rather than padding.
    public let notes: [String]

    public var isEmpty: Bool { entries.isEmpty && tally.isEmpty }
}

public extension Almanac {

    /// Reads a year back.
    ///
    /// - Parameter lineage: needed because the queens are the spine of the
    ///   story and the almanac only ever wrote their titles into prose.
    func review(year: Int, lineage: Lineage) -> YearInReview {
        let tally = tally(forYear: year) ?? YearTally(year: year)
        let lines = entries(inYear: year)

        let firstDay = (year - 1) * Season.daysPerYear
        let lastDay = firstDay + Season.daysPerYear - 1
        let reigning = lineage.queens.filter { queen in
            queen.emergedOnDay <= lastDay && (queen.endedOnDay ?? Int.max) >= firstDay
        }

        var notes: [String] = []

        if tally.peakHoney > 0 {
            notes.append("The stores reached \(Int(tally.peakHoney.rounded())) units at their highest.")
        }
        if tally.honeyTaken > 0 {
            notes.append("You took \(Int(tally.honeyTaken.rounded())) units of it.")
        }
        if tally.swarms > 0 {
            notes.append(tally.swarms == 1
                ? "The colony swarmed once, which is how colonies reproduce."
                : "The colony swarmed \(tally.swarms) times.")
        }
        if tally.splits > 0 {
            notes.append(tally.splits == 1
                ? "You divided it once, before it divided itself."
                : "You divided it \(tally.splits) times.")
        }
        if tally.combAdded > 0 {
            notes.append("You gave the bees \(tally.combAdded) cells of comb.")
        }
        if tally.queensRaised > 0 {
            notes.append(queenNote(tally))
        }
        if tally.raids > 0 {
            notes.append(raidNote(tally))
        }
        if tally.infections > 0 {
            notes.append(tally.infections == 1
                ? "One infection took hold."
                : "\(tally.infections) infections took hold.")
        }

        return YearInReview(
            year: year,
            tally: tally,
            entries: lines,
            queens: reigning,
            headline: Self.headline(for: tally, queens: reigning, year: year),
            notes: notes
        )
    }

    private func queenNote(_ tally: YearTally) -> String {
        let raised = tally.queensRaised == 1
            ? "One queen was raised"
            : "\(tally.queensRaised) queens were raised"
        // The gap between the two is the year's real risk, and it is the thing
        // a player who never watches a mating flight would otherwise never see.
        let lost = tally.queensRaised - tally.queensMated
        guard lost > 0 else { return raised + ", and every one of them mated." }
        return raised + ", and \(lost) never came back from her mating flight."
    }

    private func raidNote(_ tally: YearTally) -> String {
        let raids = tally.raids == 1 ? "One raid" : "\(tally.raids) raids"
        if tally.raidsRepelled == 0 {
            return raids + ", none of them driven off."
        }
        if tally.raidsRepelled >= tally.raids {
            return raids + ", every one driven off at the entrance."
        }
        return raids + ", \(tally.raidsRepelled) driven off at the entrance."
    }

    /// The one line, chosen by what actually dominated the year.
    private static func headline(for tally: YearTally, queens: [QueenRecord], year: Int) -> String {
        let ordinal = ["first", "second", "third", "fourth", "fifth"]
        let which = year <= ordinal.count ? ordinal[year - 1] : "\(year)th"

        if tally.isEmpty {
            return "The \(which) year, and nothing in it worth writing down yet."
        }
        if tally.swarms > 1 {
            return "The \(which) year: the colony divided \(tally.swarms) times."
        }
        if tally.swarms == 1 {
            return "The \(which) year, and the colony sent out a swarm."
        }
        if queens.count > 1 {
            return "The \(which) year, under \(queens.count) queens."
        }
        if let only = queens.first {
            return "The \(which) year, all of it under \(only.title)."
        }
        return "The \(which) year."
    }
}
