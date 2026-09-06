//
//  DailyDigest.swift
//  FlowerPowerGame
//
//  One "morning at the hive" a day, instead of a drip.
//
//  Twelve simulated days pass between a player's daily visits. Told about each
//  as it happens, they get a dozen notifications about a colony they have not
//  looked at; told once, at a time they chose, they get the news. Immediate
//  notifications are kept for the events that carry a decision — a siege, a
//  swarm — and everything else waits for the digest.
//

import Foundation
import FlowerPowerCore

public struct DailyDigest: Equatable, Sendable {

    public let title: String
    public let body: String

    /// Builds the day's summary from what happened since the last one.
    ///
    /// Returns `nil` when there is genuinely nothing to say. A quiet day in a
    /// steady colony is not news, and a notification that says "nothing
    /// happened" is the fastest way to have notifications turned off.
    public static func make(
        from report: CatchUpReport,
        snapshot: ColonySnapshot
    ) -> DailyDigest? {
        guard !report.isEmpty else { return nil }

        var lines: [String] = []

        // The headline is the colony's own sentence about itself.
        lines.append(snapshot.headline)

        if report.swarmed {
            lines.append("A swarm left.")
        }
        if report.queenMated {
            lines.append("The new queen is back and mated.")
        }
        if report.queenLost {
            lines.append("The queen is lost.")
        }
        if report.superseded {
            lines.append("The bees have replaced their queen.")
        }
        if !report.attacks.isEmpty {
            let names = Set(report.attacks.map { $0.displayName.lowercased() }).sorted()
            lines.append("Attacked by \(names.spokenList).")
        }
        if report.storesRaided > 1 {
            lines.append("\(Int(report.storesRaided.rounded())) units of stores were taken.")
        }
        if !report.newInfections.isEmpty {
            lines.append("\(report.newInfections.map(\.displayName).spokenList) found.")
        }
        if report.starved {
            lines.append("The colony went hungry.")
        }
        if report.netPopulationChange != 0, abs(report.netPopulationChange) >= 10 {
            let change = report.netPopulationChange
            lines.append(change > 0
                         ? "Up \(change) bees to \(snapshot.population.total)."
                         : "Down \(-change) bees to \(snapshot.population.total).")
        }

        // Only the headline, and a headline that says everything is fine, is
        // not worth a notification.
        if lines.count == 1, snapshot.status >= .steady, snapshot.alerts.isEmpty {
            return nil
        }

        let title: String
        switch snapshot.status {
        case .collapsed: title = "The colony is gone"
        case .critical: title = "The colony needs you"
        case .struggling: title = "A hard day at the hive"
        case .steady, .thriving: title = "Morning at the hive"
        }

        return DailyDigest(title: title, body: lines.joined(separator: " "))
    }

    /// When the digest should arrive, as an hour of the day the player picks.
    public struct Schedule: Codable, Equatable, Sendable {
        public var hour: Int
        public var minute: Int

        public init(hour: Int = 8, minute: Int = 0) {
            self.hour = min(23, max(0, hour))
            self.minute = min(59, max(0, minute))
        }

        public static let `default` = Schedule()
    }
}

extension Array where Element == String {

    /// "a", "a and b", "a, b and c". Foundation's list formatting is not
    /// present on every platform the package builds on, and this is all that
    /// was wanted from it.
    public var spokenList: String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        case 2: return "\(self[0]) and \(self[1])"
        default: return dropLast().joined(separator: ", ") + " and " + (last ?? "")
        }
    }
}
