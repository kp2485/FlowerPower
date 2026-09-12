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

    /// A decision waiting to be answered, with the answers.
    ///
    /// The reason the watch exists. Everything else here is a report; this is
    /// the colony asking for something, and it is answerable from the wrist
    /// without the phone being taken out of a pocket.
    public let decision: WatchDecision?

    public var hasDecision: Bool { decision != nil }

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

/// A decision the colony is waiting on, small enough to answer on a watch.
///
/// The options carry `DecisionAction` identifiers as plain strings. They are
/// spelled out here rather than built from the enum because `DecisionAction`
/// lives a layer up, in `FlowerPowerGame` with the store it applies to, and the
/// engine cannot see it. The string is the seam, and `DecisionActionTests`
/// holds it honest by parsing every option a summary produces.
///
/// Nothing here is a *new* judgement about what the player should be asked.
/// `ColonyNews` already decides that for notifications, and this asks the same
/// four questions in the same order, from the same state.
public struct WatchDecision: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case siege
        case swarm
        case nestFull
        case entrance
    }

    public struct Option: Codable, Equatable, Sendable {
        /// A `DecisionAction` identifier. Sent back to the phone as it is.
        public let identifier: String
        public let title: String

        public init(identifier: String, title: String) {
            self.identifier = identifier
            self.title = title
        }
    }

    public let kind: Kind
    /// Two or three words.
    public let title: String
    /// A sentence: what is happening and what the choice costs.
    public let detail: String
    public let options: [Option]
    /// Simulated days left to answer, where the decision has a window.
    /// Nil where it is a state rather than a countdown.
    public let daysRemaining: Int?

    public init(
        kind: Kind,
        title: String,
        detail: String,
        options: [Option],
        daysRemaining: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.options = options
        self.daysRemaining = daysRemaining
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
            decision: decision(snapshot),
            isForaging: snapshot.isForaging,
            temperatureCelsius: hive.temperatureCelsius,
            honey: hive.resources[.honey],
            generatedAt: now
        )
    }

    /// The decision in front of the player, if there is one.
    ///
    /// Only ever one. A watch has room for one page of buttons and a glance
    /// has room for one question, so where two things are open at once the
    /// more urgent wins — and the order is the one `ColonyNews` already uses,
    /// which is roughly how little time there is to answer.
    ///
    /// A decision the player has already answered is not open. That is why the
    /// siege case asks about the posture and the swarm case asks whether it has
    /// been discouraged: without those the watch would keep asking a question
    /// that has been settled, which is how an idle game turns into a pager.
    ///
    /// Following a departed swarm is deliberately not here. It needs a site
    /// chosen, which needs the phone, and offering only "Stay" would be
    /// pushing the player at the answer that happens to fit on a watch.
    private func decision(_ snapshot: ColonySnapshot) -> WatchDecision? {
        let posturePrefix = "posture."

        if let threat = world.activeThreat, threat.style.hasAnswer, world.posture == .instinct {
            return WatchDecision(
                kind: .siege,
                title: "\(threat.predator.displayName) at the nest",
                detail: threat.style.explanation,
                options: HivePosture.options(against: threat.style)
                    .filter { $0 != .instinct }
                    .map { WatchDecision.Option(
                        identifier: posturePrefix + $0.rawValue,
                        title: $0.displayName
                    ) },
                daysRemaining: threat.daysRemaining(on: clock.day)
            )
        }

        if let swarm = world.pendingSwarm, !swarm.discouraged {
            // Ordered by what the measurement says rather than by what was
            // built last. Over 200 colonies across two years, two-year
            // survival is 76% for making room, 66% for doing nothing at all,
            // 62% for adding comb and 56% for dividing — so talking them out
            // of it goes first and the newest mechanics do not.
            var options = [WatchDecision.Option(
                identifier: "swarm.discourage", title: "Make Room"
            )]
            // Both halves of the question: room the site can give, and honey
            // to draw comb into it. Wax costs about seven times its weight in
            // stores, so a colony in a dearth cannot use room it is given —
            // and a button that does nothing is worse than no button.
            if canAddComb, canAffordComb {
                options.append(.init(identifier: "nest.addComb", title: "Open the Nest Up"))
            }
            if canSplit {
                options.append(.init(identifier: "swarm.split", title: "Divide Them"))
            }
            options.append(.init(identifier: "swarm.let", title: "Let Them Go"))

            return WatchDecision(
                kind: .swarm,
                title: "Preparing to swarm",
                detail: "Swarm cells are started. The old queen will leave with most of the flying bees unless something changes.",
                options: options,
                daysRemaining: swarm.daysRemaining(on: clock.day)
            )
        }

        // The week before the cells, when space is still cheap. Said only
        // while there is room to give, because the one answer to it is room.
        if world.hive.combOccupancy >= 0.9,
           world.hive.comb.builtCells >= world.hive.comb.capacity,
           canAddComb, canAffordComb {
            return WatchDecision(
                kind: .nestFull,
                title: "The nest is full",
                detail: "Every cell is drawn and the cavity is worked out. Open the nest up and they keep building; leave it and they divide instead.",
                options: [.init(identifier: "nest.addComb", title: "Open the Nest Up")]
            )
        }

        if season == .autumn, world.entranceDecision == nil, !world.entranceSealed {
            return WatchDecision(
                kind: .entrance,
                title: "Autumn: the entrance",
                detail: "The bees will narrow the entrance with propolis unless you keep it open. Sealed keeps mice out and the damp in.",
                options: [
                    .init(identifier: "entrance.seal", title: "Seal It"),
                    .init(identifier: "entrance.open", title: "Keep It Open")
                ]
            )
        }

        return nil
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
        if world.isInFlow(config) { return "Flowing" }
        if world.isInDearth(config) { return "Dearth" }
        if snapshot.isForaging { return "Foraging" }
        return snapshot.status.displayName
    }
}
