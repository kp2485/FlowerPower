//
//  History.swift
//  FlowerPowerCore
//
//  The colony's numbers over time, so the game can show a trajectory and not
//  only a state.
//
//  The almanac says what happened. It does not say how big the colony was
//  while it happened, and that is most of what a hive record is for: the
//  questions a player actually has — was this winter worse than the last one,
//  did the split cost me the flow, is the cluster shrinking faster than it
//  should — are questions about a shape rather than a number. The dashboard
//  shows the present, the almanac shows the prose, and neither of them can
//  answer any of those.
//
//  One sample a day, written by `HistorySystem` at the day boundary. Kept
//  small on purpose: it goes in the save file, and two years of it is seven
//  hundred of them. Anything derivable from the day — the season, the year —
//  is computed rather than stored, so it costs nothing to keep.
//

import Foundation

// MARK: - A day

/// The colony as it stood on one day, in the handful of numbers worth
/// charting.
///
/// A reading, not a summary: every field is what the hive actually held at the
/// moment the sample was taken, which is what makes the charts trustworthy.
/// The one exception is `nectarIntake`, and it says why.
public struct DailySample: Codable, Equatable, Sendable, Identifiable {

    public let day: Int

    // MARK: Population

    public let adults: Int
    public let brood: Int
    public let workers: Int
    public let drones: Int
    /// Long-lived autumn bees. The single best predictor of whether a colony
    /// sees spring, and invisible in a plain population count.
    public let winterBees: Int

    // MARK: Stores

    /// Honey equivalent of everything edible in the hive, exactly as
    /// `ColonySnapshot` computes it.
    public let edibleEnergy: Double
    /// What it would take to see this colony through to spring, as judged on
    /// the day. It moves with the size of the cluster, so the gap between the
    /// two lines is the story and neither line alone is.
    public let winterRequirement: Double

    // MARK: Nest

    public let nestTemperature: Double
    public let outsideTemperature: Double
    public let combCells: Int

    // MARK: The day's work

    /// Nectar gathered over the day that has just closed.
    ///
    /// The only backward-looking figure here, because it is the only one that
    /// cannot be known about a day at its start. This is the same convention
    /// `ColonySnapshot.dailyNectarIntake` uses, and the two agree.
    public let nectarIntake: Double

    public let alarm: Double
    public let status: ColonyStatus

    public init(
        day: Int,
        adults: Int,
        brood: Int,
        workers: Int,
        drones: Int,
        winterBees: Int,
        edibleEnergy: Double,
        winterRequirement: Double,
        nestTemperature: Double,
        outsideTemperature: Double,
        combCells: Int,
        nectarIntake: Double,
        alarm: Double,
        status: ColonyStatus
    ) {
        self.day = day
        self.adults = adults
        self.brood = brood
        self.workers = workers
        self.drones = drones
        self.winterBees = winterBees
        self.edibleEnergy = edibleEnergy
        self.winterRequirement = winterRequirement
        self.nestTemperature = nestTemperature
        self.outsideTemperature = outsideTemperature
        self.combCells = combCells
        self.nectarIntake = nectarIntake
        self.alarm = alarm
        self.status = status
    }

    public var id: Int { day }

    /// Derived rather than stored: the season is a fact about the date, and a
    /// string per sample in every save file for something the calendar already
    /// knows would be a waste of both.
    public var season: Season { Season(day: day) }
    public var year: Int { day / Season.daysPerYear + 1 }
    public var dayOfYear: Int { day % Season.daysPerYear + 1 }

    /// Everything alive in the nest, brood included.
    public var population: Int { adults + brood }

    /// How far through the winter provisioning the colony was, 0...1.
    public var winterReadiness: Double {
        guard winterRequirement > 0 else { return 1 }
        return min(1, max(0, edibleEnergy / winterRequirement))
    }
}

// MARK: - The record

public struct ColonyHistory: Codable, Equatable, Sendable {

    /// Oldest first, one per simulated day, no gaps while the colony is being
    /// simulated.
    public private(set) var samples: [DailySample]

    /// Two years, which is longer than most colonies live and further back
    /// than any chart in the game looks. Beyond it the oldest days go.
    public static let limit = Season.daysPerYear * 2

    public init(samples: [DailySample] = []) {
        self.samples = samples
    }

    /// Written by hand for the same reason `World.init(from:)` is, and then
    /// one reason more: a save whose history cannot be read opens without it
    /// rather than failing to open at all.
    ///
    /// The record is the most disposable thing in the file and the likeliest
    /// to gain a field later. Losing a colony's charts to a format change is a
    /// disappointment; losing the colony is not survivable, and `GameStore`
    /// treats an unreadable save as no save.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        samples = (try? container.decodeIfPresent([DailySample].self, forKey: .samples)) ?? []
    }

    public var isEmpty: Bool { samples.isEmpty }

    public var firstDay: Int? { samples.first?.day }
    public var lastDay: Int? { samples.last?.day }

    /// Records a day.
    ///
    /// A day already in the record is left as it was. The system calls this
    /// once per day boundary and so cannot repeat one, but a chart with two
    /// points for one day is unreadable, and that invariant is worth stating
    /// here rather than trusting to the caller.
    public mutating func append(_ sample: DailySample) {
        if let last = lastDay, sample.day <= last { return }
        samples.append(sample)
        if samples.count > Self.limit {
            samples.removeFirst(samples.count - Self.limit)
        }
    }

    // MARK: Reading it back

    public func samples(inYear year: Int) -> [DailySample] {
        samples.filter { $0.year == year }
    }

    public func samples(onOrAfterDay day: Int) -> [DailySample] {
        samples.filter { $0.day >= day }
    }

    /// The last `days` days of the record, counted back from the newest
    /// sample rather than from the clock — a colony that has not been
    /// simulated for a week should still show its last week.
    public func recent(_ days: Int) -> [DailySample] {
        guard let last = lastDay, days > 0 else { return [] }
        return samples(onOrAfterDay: last - (days - 1))
    }

    /// The samples a range picker asks for.
    public func samples(in range: HistoryRange, endingOn day: Int) -> [DailySample] {
        guard let first = range.firstDay(endingOn: day) else { return samples }
        return samples(onOrAfterDay: first)
    }

    /// The range the record can actually offer, so a picker need not show
    /// choices that would come back empty.
    public func offers(_ range: HistoryRange, endingOn day: Int) -> Bool {
        !samples(in: range, endingOn: day).isEmpty
    }
}

// MARK: - Ranges

/// How far back a chart looks.
///
/// In the package rather than in the view because the arithmetic is about the
/// game's calendar — a season is ninety days and a year is four of those — and
/// because the compiler can then check that every case is handled.
public enum HistoryRange: String, CaseIterable, Codable, Sendable, Identifiable {

    case month
    case season
    case year
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .month: return "30 days"
        case .season: return "Season"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    /// The first day the range includes, given the day it ends on, or `nil`
    /// for the whole record.
    public func firstDay(endingOn day: Int) -> Int? {
        switch self {
        case .month: return day - 29
        case .season: return day - Season.dayOfSeason(day)
        case .year: return day - (((day % Season.daysPerYear) + Season.daysPerYear) % Season.daysPerYear)
        case .all: return nil
        }
    }
}

// MARK: - Seasons, as bands

/// A run of consecutive days in one season.
///
/// The population chart is unreadable without the seasons drawn behind it: a
/// colony halving in size is alarming in June and simply what October looks
/// like. Computed here so the shading is the same wherever it is drawn, and so
/// the run-finding is tested rather than written into a view nothing on this
/// machine can compile.
public struct SeasonSpan: Equatable, Sendable, Identifiable {

    public let season: Season
    public let firstDay: Int
    public let lastDay: Int

    public init(season: Season, firstDay: Int, lastDay: Int) {
        self.season = season
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    public var id: Int { firstDay }

    /// Groups samples into the seasons they fall in, oldest first.
    public static func spans(covering samples: [DailySample]) -> [SeasonSpan] {
        var spans: [SeasonSpan] = []
        for sample in samples {
            if let open = spans.last, open.season == sample.season {
                spans[spans.count - 1] = SeasonSpan(
                    season: open.season,
                    firstDay: open.firstDay,
                    lastDay: sample.day
                )
            } else {
                spans.append(
                    SeasonSpan(season: sample.season, firstDay: sample.day, lastDay: sample.day)
                )
            }
        }
        return spans
    }
}
