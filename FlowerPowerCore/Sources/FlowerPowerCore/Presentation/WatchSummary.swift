//
//  WatchSummary.swift
//  FlowerPowerCore
//
//  The watch has a different job from the phone. The phone is where you
//  photograph flowers, browse the map and study the comb. The watch is where
//  you find out, in the second and a half you look at it, whether the colony
//  needs you.
//
//  So this is not a smaller `ColonySnapshot` — it is a different question
//  answered. It is also small enough to send over WatchConnectivity and to back
//  a complication without unpacking the whole world.
//

import Foundation

public struct WatchSummary: Codable, Equatable, Sendable {

    public let status: ColonyStatus

    /// Two or three words. This is the complication's text.
    public let shortHeadline: String
    /// One sentence, for the watch app's main view.
    public let headline: String

    public let population: Int
    public let broodCount: Int
    public let season: Season
    public let day: Int

    /// The gauge value a complication renders, 0...1, and what it means.
    public let gauge: Gauge

    /// The single most urgent thing wrong, if anything is.
    public let topAlert: ColonyAlert?

    /// Whether the bees are flying right now.
    public let isForaging: Bool

    public let temperatureCelsius: Double
    public let honey: Double

    public let generatedAt: Date

    public struct Gauge: Codable, Equatable, Sendable {

        public enum Meaning: String, Codable, Sendable {
            case winterStores
            case combSpace
            case health
            case population

            public var label: String {
                switch self {
                case .winterStores: return "Winter Stores"
                case .combSpace: return "Nest Space"
                case .health: return "Health"
                case .population: return "Colony"
                }
            }
        }

        public let meaning: Meaning
        /// 0...1, where 1 is good.
        public let value: Double
        public let caption: String
    }
}

extension Simulation {

    /// Builds the watch payload.
    public func watchSummary(now: Date = Date()) -> WatchSummary {
        let snapshot = self.snapshot()
        let hive = world.hive

        return WatchSummary(
            status: snapshot.status,
            shortHeadline: shortHeadline(snapshot),
            headline: snapshot.headline,
            population: hive.population,
            broodCount: hive.broodCount,
            season: snapshot.season,
            day: snapshot.day,
            gauge: gauge(snapshot),
            topAlert: snapshot.alerts.first,
            isForaging: snapshot.isForaging,
            temperatureCelsius: hive.temperatureCelsius,
            honey: hive.resources[.honey],
            generatedAt: now
        )
    }

    /// Picks the one measure that matters most right now.
    ///
    /// A complication has room for a single gauge, so showing a fixed metric
    /// would waste it for most of the year. In autumn nothing matters but
    /// winter stores; in a crisis nothing matters but the crisis; during a
    /// summer flow the interesting question is whether the nest has room.
    private func gauge(_ snapshot: ColonySnapshot) -> WatchSummary.Gauge {
        let hive = world.hive

        if snapshot.status == .critical || hive.pathogens.totalPressure > 0.4 {
            let health = 1 - hive.pathogens.totalPressure
            return WatchSummary.Gauge(
                meaning: .health,
                value: max(0, min(1, health)),
                caption: hive.pathogens.dominant.map { $0.pathogen.displayName } ?? "Colony health"
            )
        }

        if season == .autumn || season == .winter {
            return WatchSummary.Gauge(
                meaning: .winterStores,
                value: snapshot.stores.winterReadiness,
                caption: String(
                    format: "%.0f of %.0f",
                    snapshot.stores.edibleEnergy,
                    snapshot.stores.winterRequirement
                )
            )
        }

        if hive.combOccupancy > 0.75 {
            return WatchSummary.Gauge(
                meaning: .combSpace,
                value: max(0, 1 - hive.combOccupancy),
                caption: "\(hive.freeCells) cells free"
            )
        }

        // Otherwise, how the colony is growing against what the nest can hold.
        let capacity = max(1, hive.comb.capacity)
        return WatchSummary.Gauge(
            meaning: .population,
            value: min(1, Double(hive.population) / Double(capacity)),
            caption: "\(hive.population) bees"
        )
    }

    /// Two or three words for a complication.
    private func shortHeadline(_ snapshot: ColonySnapshot) -> String {
        if let alert = snapshot.alerts.first, alert.severity >= .warning {
            return alert.title
        }
        if !world.weather.isFlyingWeather { return "Grounded" }
        if season == .winter { return "Clustered" }
        if world.isInFlow { return "Flowing" }
        if world.isInDearth { return "Dearth" }
        if snapshot.isForaging { return "Foraging" }
        return snapshot.status.displayName
    }
}
