//
//  Season.swift
//  FlowerPowerCore
//

import Foundation

public enum Season: String, Codable, CaseIterable, Sendable {
    case spring
    case summer
    case autumn
    case winter

    public static let daysPerSeason = 90
    public static let daysPerYear = daysPerSeason * 4

    public init(day: Int) {
        let dayOfYear = ((day % Self.daysPerYear) + Self.daysPerYear) % Self.daysPerYear
        switch dayOfYear / Self.daysPerSeason {
        case 0: self = .spring
        case 1: self = .summer
        case 2: self = .autumn
        default: self = .winter
        }
    }

    public var displayName: String { rawValue.capitalized }

    /// How much nectar and pollen the landscape is offering. Real colonies see
    /// a spring build-up, a main summer flow, an autumn dearth and nothing at
    /// all in winter.
    public var forageMultiplier: Double {
        switch self {
        case .spring: return 0.9
        case .summer: return 1.25
        // The autumn flow — heather, ivy, balsam — is what a colony actually
        // winters on. Treating autumn as a pure dearth left colonies unable to
        // top up their stores after the summer flow ended, and they starved in
        // February with the year's honey already eaten.
        case .autumn: return 0.65
        case .winter: return 0.0
        }
    }

    /// Flowering plants replenish nectar overnight, but not out of season.
    public var patchRegrowthMultiplier: Double {
        switch self {
        case .spring: return 1.0
        case .summer: return 1.2
        case .autumn: return 0.35
        case .winter: return 0.0
        }
    }

    public var weatherNormals: WeatherNormals {
        switch self {
        case .spring:
            return WeatherNormals(
                meanTemperature: 17,
                temperatureSwing: 8,
                skyDistribution: WeightedChoice([
                    (.clear, 4), (.cloudy, 4), (.rain, 2), (.storm, 0.4)
                ])
            )
        case .summer:
            return WeatherNormals(
                meanTemperature: 25,
                temperatureSwing: 7,
                skyDistribution: WeightedChoice([
                    (.clear, 6), (.cloudy, 3), (.rain, 1.2), (.storm, 0.5)
                ])
            )
        case .autumn:
            return WeatherNormals(
                meanTemperature: 12,
                temperatureSwing: 8,
                skyDistribution: WeightedChoice([
                    (.clear, 3), (.cloudy, 4), (.rain, 3), (.storm, 0.6)
                ])
            )
        case .winter:
            return WeatherNormals(
                meanTemperature: 2,
                temperatureSwing: 9,
                skyDistribution: WeightedChoice([
                    (.clear, 3), (.cloudy, 4), (.rain, 2.5), (.storm, 0.8)
                ])
            )
        }
    }

    /// Day within the season, 0-based. Used to taper behaviour across a season
    /// instead of switching abruptly at the boundary.
    public static func dayOfSeason(_ day: Int) -> Int {
        let dayOfYear = ((day % daysPerYear) + daysPerYear) % daysPerYear
        return dayOfYear % daysPerSeason
    }

    /// Progress through the season, 0...1.
    public static func progress(_ day: Int) -> Double {
        Double(dayOfSeason(day)) / Double(daysPerSeason)
    }

    /// Point in summer at which the colony switches from building a workforce
    /// to rearing the winter cohort.
    public static let winterRearingStartsAtSummerProgress = 0.6

    /// Point in spring before which a colony will not swarm.
    ///
    /// Swarming is the *product* of the spring build-up, not its opening move.
    /// A colony comes out of winter as a small cluster on the last of its
    /// stores and spends six or eight weeks rebuilding; only once it is
    /// crowded, with the flow on and stores back, does it divide. Real
    /// swarming peaks in May, not in the first fortnight of March.
    ///
    /// Without this the model let a colony swarm on spring day 16, straight
    /// out of winter, shedding sixty per cent of its workers while it still
    /// had a hundred units of honey to last until the flow. It is the one
    /// moment in the year a colony can least afford to halve itself.
    public static let swarmSeasonStartsAtSpringProgress = 0.45

    /// Point in summer past which a colony will no longer swarm. Real swarming
    /// is concentrated around the spring flow; dividing later leaves neither
    /// half time to provision for winter.
    public static let swarmSeasonEndsAtSummerProgress = 0.35

    /// Point through winter at which the cluster loosens, the nest warms, and
    /// the winter bees resume developing into nurses ahead of the first brood.
    public static let winterDormancyEnds = 0.5

    /// Days from `day` until the start of the next spring. The horizon a
    /// colony is provisioning against.
    public static func daysUntilSpring(from day: Int) -> Int {
        let dayOfYear = ((day % daysPerYear) + daysPerYear) % daysPerYear
        return dayOfYear == 0 ? 0 : daysPerYear - dayOfYear
    }

    /// Whether a wintering bee is still clustered and idle on this day, rather
    /// than working. Behavioural development is suspended while she is.
    public static func isClusterDormant(on day: Int) -> Bool {
        // Autumn is a working season — the ivy flow is on and there is still
        // brood to rear. Only the true winter cluster is idle.
        guard Season(day: day) == .winter else { return false }
        return progress(day) < winterDormancyEnds
    }

    /// Whether brood reared on this day will emerge as long-lived winter bees.
    ///
    /// This begins in late summer, not at the autumn boundary. Brood laid in
    /// August emerges in September and is the backbone of the winter cluster —
    /// treating autumn as the cutoff meant the constraint on how many winter
    /// bees a colony could afford arrived after most of them had already been
    /// committed to.
    public static func isRearingWinterBees(on day: Int) -> Bool {
        switch Season(day: day) {
        case .autumn, .winter:
            return true
        case .summer:
            return progress(day) >= winterRearingStartsAtSummerProgress
        case .spring:
            return false
        }
    }
}
