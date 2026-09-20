//
//  ReportDigest.swift
//  FlowerPowerGame
//
//  The catch-up report, condensed.
//
//  `CatchUpReport.highlights` is a timeline: up to sixty sentences in the
//  order they happened. That is the right thing for the engine to hand over
//  and the wrong thing to put on the screen a player sees first thing in the
//  morning. A fortnight away produces a wall of prose in which the sentence
//  saying the queen was lost sits between two saying the weather turned, and
//  one chatty kind of event — a flower going out of season fires once per
//  patch per season change — can fill the whole cap on its own and push
//  everything that mattered out of it.
//
//  So the lines are grouped by what a player would call them, ordered by how
//  much they matter, counted, and capped *per group*. Two things follow from
//  the per-group cap, and both are the point: no kind of event can crowd out
//  another however many times it fires, and the screen can open showing one
//  summary line per group with the detail a tap away.
//
//  All of it is arithmetic over a value type, so it is compiled and tested
//  here rather than written into a view on a machine that cannot build one.
//

import Foundation
import FlowerPowerCore

// MARK: - What a player would call it

/// The half-dozen kinds of news a catch-up report carries.
///
/// Not the engine's categories — `SimEvent`'s own grouping is by which system
/// emitted it, which is a fact about the code. This is the grouping somebody
/// reading the screen already has in their head: how the colony is doing, who
/// came for it, whether it is ill, what there was to eat, what the nest looks
/// like, what they themselves asked for, and what it managed for the first
/// time.
///
/// The declaration order is the tie-break when two groups are equally severe,
/// so it reads worst-case first: a lost queen before a hornet before a mite.
public enum HighlightCategory: String, CaseIterable, Codable, Sendable {

    case colony
    case defence
    case health
    case forage
    case nest
    case keeping
    case firsts

    /// The group's heading.
    public var displayName: String {
        switch self {
        case .colony: return "The colony"
        case .defence: return "Defence"
        case .health: return "Health"
        case .forage: return "Forage and weather"
        case .nest: return "The nest"
        case .keeping: return "Your keeping"
        case .firsts: return "Firsts"
        }
    }

    public var symbolName: String {
        switch self {
        case .colony: return "person.3.fill"
        case .defence: return "shield.slash.fill"
        case .health: return "cross.case.fill"
        case .forage: return "camera.macro"
        case .nest: return "square.grid.3x3.fill"
        case .keeping: return "hand.raised.fill"
        case .firsts: return "rosette"
        }
    }
}

public extension SimEvent {

    /// Which heading this event belongs under.
    ///
    /// Exhaustive on purpose. A case added to the engine and forgotten here
    /// would silently fall into whatever the default was, and the whole value
    /// of the grouping is that a player can trust the heading.
    var category: HighlightCategory {
        switch self {

        case .emerged, .died, .eggsLaid, .queenCellStarted, .queenEmerged,
             .queenMated, .matingFlightFailed, .queenLost, .queenFailing,
             .swarmed, .absconded, .supersededQueen, .layingWorkersAppeared,
             .colonyCollapsed, .swarmPreparing, .swarmAbandoned, .colonyDivided:
            return .colony

        case .attacked, .attackRepelled, .raidSucceeded, .threatBegan,
             .threatEnded:
            return .defence

        case .infectionDetected, .infectionCleared, .infectionCritical:
            return .health

        case .patchDepleted, .patchOutOfBloom, .nectarFlowBegan, .dearth,
             .weatherChanged, .groundedByWeather, .starving, .winterStoresLow:
            return .forage

        case .cellsBuilt, .combLost, .overheating, .chilling:
            return .nest

        case .postureAdopted, .entranceSealed, .honeyTaken, .fed, .combAdded:
            return .keeping

        case .milestone:
            return .firsts
        }
    }

    /// The two or three words the group's summary counts this event in — "3
    /// raids, 2 driven off".
    ///
    /// Distinct from `narration`, which is a whole sentence about one
    /// occurrence and cannot be counted. Kept deliberately bare of the event's
    /// payload for the same reason: a summary that said "hornet raid" and
    /// "badger raid" separately would not be a summary.
    var digestPhrase: DigestPhrase {
        switch self {

        // Population
        case .emerged: return DigestPhrase("emergence", "emergences")
        case .died: return DigestPhrase("death", "deaths")
        case .eggsLaid: return DigestPhrase("laying", "layings")

        // Colony lifecycle
        case .queenCellStarted: return DigestPhrase("queen cell", "queen cells")
        case .queenEmerged: return DigestPhrase("new queen", "new queens")
        case .queenMated: return DigestPhrase("mating flight", "mating flights")
        case .matingFlightFailed: return DigestPhrase("failed mating", "failed matings")
        case .queenLost: return DigestPhrase("queen lost", "queens lost")
        case .queenFailing: return DigestPhrase("queen failing", "queens failing")
        case .swarmed: return DigestPhrase("swarm", "swarms")
        case .absconded: return DigestPhrase("absconding", "abscondings")
        case .supersededQueen: return DigestPhrase("supersedure", "supersedures")
        case .layingWorkersAppeared: return DigestPhrase("laying workers", "laying workers")
        case .colonyCollapsed: return DigestPhrase("collapse", "collapses")
        case .swarmPreparing: return DigestPhrase("swarm brewing", "swarms brewing")
        case .swarmAbandoned: return DigestPhrase("swarm called off", "swarms called off")
        case .colonyDivided: return DigestPhrase("division", "divisions")

        // Defence
        case .attacked: return DigestPhrase("attack", "attacks")
        case .attackRepelled: return DigestPhrase("attack driven off", "driven off")
        case .raidSucceeded: return DigestPhrase("raid", "raids")
        case .threatBegan: return DigestPhrase("siege", "sieges")
        case .threatEnded: return DigestPhrase("siege lifted", "sieges lifted")

        // Health
        case .infectionDetected: return DigestPhrase("infection", "infections")
        case .infectionCleared: return DigestPhrase("infection cleared", "infections cleared")
        case .infectionCritical: return DigestPhrase("critical infection", "critical infections")

        // Forage and weather
        case .patchDepleted: return DigestPhrase("patch worked out", "patches worked out")
        case .patchOutOfBloom: return DigestPhrase("flower out of season", "flowers out of season")
        case .nectarFlowBegan: return DigestPhrase("flow", "flows")
        case .dearth: return DigestPhrase("dearth", "dearths")
        case .weatherChanged: return DigestPhrase("change in the weather", "changes in the weather")
        case .groundedByWeather: return DigestPhrase("day grounded", "days grounded")
        case .starving: return DigestPhrase("hungry spell", "hungry spells")
        case .winterStoresLow: return DigestPhrase("warning on the stores", "warnings on the stores")

        // The nest
        case .cellsBuilt: return DigestPhrase("building", "buildings")
        case .combLost: return DigestPhrase("comb lost", "combs lost")
        case .overheating: return DigestPhrase("overheating", "overheatings")
        case .chilling: return DigestPhrase("chilling", "chillings")

        // Your keeping
        case .postureAdopted: return DigestPhrase("change of posture", "changes of posture")
        case .entranceSealed: return DigestPhrase("entrance decided", "entrance decisions")
        case .honeyTaken: return DigestPhrase("harvest", "harvests")
        case .fed: return DigestPhrase("feed", "feeds")
        case .combAdded: return DigestPhrase("room added", "roomings added")

        // The record
        case .milestone: return DigestPhrase("first", "firsts")
        }
    }
}

/// A countable name for a kind of event, in both numbers.
///
/// English has no rule that gets "3 raids" and "2 driven off" out of one
/// string, so both are written down.
public struct DigestPhrase: Equatable, Sendable {

    public let singular: String
    public let plural: String

    public init(_ singular: String, _ plural: String) {
        self.singular = singular
        self.plural = plural
    }

    /// "1 raid", "3 raids".
    public func counted(_ count: Int) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

// MARK: - The digest

/// `CatchUpReport.highlights`, grouped, counted and capped.
public struct ReportDigest: Equatable, Sendable {

    /// How many lines a group shows before it starts saying "and 9 more".
    ///
    /// Four, because the point of the cap is that a group cannot fill the
    /// screen: five groups of four is a page a player can take in, and the
    /// rest is one tap away.
    public static let defaultLinesPerGroup = 4

    /// Worst first, and never empty of events.
    public let groups: [Group]

    /// Every highlight the report carried, before any capping.
    public let totalCount: Int

    public init(
        highlights: [SimEvent],
        linesPerGroup: Int = ReportDigest.defaultLinesPerGroup
    ) {
        totalCount = highlights.count

        // Arrival order is kept inside a group — a group is a little
        // timeline — so the events are bucketed by a pass over the list
        // rather than by sorting it.
        var order: [HighlightCategory] = []
        var buckets: [HighlightCategory: [SimEvent]] = [:]
        for event in highlights {
            let category = event.category
            if buckets[category] == nil { order.append(category) }
            buckets[category, default: []].append(event)
        }

        let cap = max(1, linesPerGroup)
        groups = order
            .compactMap { category in
                buckets[category].map {
                    Group(category: category, events: $0, linesPerGroup: cap)
                }
            }
            // Severity first, then the category's own declaration order, so
            // two equally grave groups always come out the same way round.
            .sorted { left, right in
                if left.severity != right.severity { return left.severity > right.severity }
                return left.category.sortIndex < right.category.sortIndex
            }
    }

    public init(
        report: CatchUpReport,
        linesPerGroup: Int = ReportDigest.defaultLinesPerGroup
    ) {
        self.init(highlights: report.highlights, linesPerGroup: linesPerGroup)
    }

    public var isEmpty: Bool { groups.isEmpty }

    /// The group under a given heading, for a caller that wants one.
    public func group(_ category: HighlightCategory) -> Group? {
        groups.first { $0.category == category }
    }
}

public extension ReportDigest {

    /// One heading's worth of news.
    struct Group: Identifiable, Equatable, Sendable {

        public let category: HighlightCategory
        /// Everything that fell under the heading, in the order it happened.
        public let events: [SimEvent]
        public let linesPerGroup: Int

        /// The distinct sentences, in first-appearance order, each with how
        /// many times it happened.
        ///
        /// Folded by sentence rather than listed one per event, because four
        /// identical lines reading "A flower went out of season." is the
        /// failure this whole file exists to prevent, and showing it once with
        /// a count beside it says strictly more in a quarter of the room.
        public let lines: [Line]

        public init(category: HighlightCategory, events: [SimEvent], linesPerGroup: Int) {
            self.category = category
            self.events = events
            self.linesPerGroup = max(1, linesPerGroup)

            var order: [String] = []
            var counts: [String: Int] = [:]
            var severities: [String: SimEvent.Severity] = [:]
            for event in events {
                let text = event.narration
                if counts[text] == nil {
                    order.append(text)
                    severities[text] = event.severity
                }
                counts[text, default: 0] += 1
            }
            lines = order.map { text in
                Line(
                    text: text,
                    count: counts[text] ?? 1,
                    severity: severities[text] ?? .routine
                )
            }
        }

        public var id: String { category.rawValue }

        /// How many things happened under this heading.
        public var count: Int { events.count }

        /// The gravest thing in the group, which is what orders it against
        /// the others.
        public var severity: SimEvent.Severity {
            events.map(\.severity).max() ?? .routine
        }

        /// What the collapsed row says: "3 raids, 2 driven off".
        ///
        /// Counted by kind rather than by sentence, so a hornet raid and a
        /// badger raid are two raids. Kinds appear in the order they first
        /// did.
        public var summary: String {
            var order: [String] = []
            var counts: [String: Int] = [:]
            var phrases: [String: DigestPhrase] = [:]
            for event in events {
                let phrase = event.digestPhrase
                let key = phrase.singular
                if counts[key] == nil {
                    order.append(key)
                    phrases[key] = phrase
                }
                counts[key, default: 0] += 1
            }
            return order
                .compactMap { key in
                    phrases[key].map { $0.counted(counts[key] ?? 1) }
                }
                .joined(separator: ", ")
        }

        /// The lines a collapsed group is allowed to show.
        public var visibleLines: [Line] { Array(lines.prefix(linesPerGroup)) }

        /// How many events are in the lines that did not fit.
        public var hiddenCount: Int {
            lines.dropFirst(linesPerGroup).reduce(0) { $0 + $1.count }
        }

        /// "and 9 more", or nothing when it all fitted.
        public var overflowLine: String? {
            hiddenCount > 0 ? "and \(hiddenCount) more" : nil
        }
    }

    /// One sentence, and how many times it was true.
    struct Line: Identifiable, Equatable, Sendable {

        public let text: String
        public let count: Int
        public let severity: SimEvent.Severity

        public init(text: String, count: Int, severity: SimEvent.Severity) {
            self.text = text
            self.count = count
            self.severity = severity
        }

        public var id: String { text }

        /// The sentence as it is read, with the count only when there is one
        /// worth saying.
        public var display: String {
            count > 1 ? "\(text) ×\(count)" : text
        }
    }
}

private extension HighlightCategory {

    /// Position in `allCases`, which is the declaration order the doc comment
    /// on this enum promises.
    var sortIndex: Int {
        HighlightCategory.allCases.firstIndex(of: self) ?? 0
    }
}
