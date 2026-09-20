//
//  LiveActivityPlan.swift
//  FlowerPowerGame
//
//  Which Live Activities should be on the lock screen right now, and for how
//  much longer.
//
//  This judgement used to live in the app, next to ActivityKit, and it had one
//  rule: a card is up for as long as the thing it is about is happening. That
//  sounds right and is wrong for this game, because the game's clock is slow.
//  A skunk works a nest for three simulated days, which is six real hours, and
//  a swarm gathers for eight, which is most of a real day — and the card sat
//  on the lock screen and in the Dynamic Island for all of it, then for up to
//  four hours more, because that is what iOS does with an activity ended
//  under the default dismissal policy. The first player to see one said it
//  stayed "way too long", and it had.
//
//  A Live Activity is for the part of an event that wants the player's
//  attention, not for the event. So:
//
//  - **A card is up only while there is something to decide.** A siege the
//    player has answered, or a swarm they have made room for, comes down at
//    once: the tap was the point, and a card that stays up afterwards is a
//    card telling someone about a thing they have already dealt with.
//  - **And never for longer than a simulated day**, which is about two real
//    hours. Nobody is punished for being at work — instinct is the default —
//    so a question still unanswered after that has been answered by not
//    answering, and the card goes. The decision itself stays open on the
//    dashboard for as long as the engine keeps it open; this is only about
//    what is held in front of someone who did not ask to look.
//
//  It is here rather than in the app for the usual reason: this is a
//  judgement about engine state, and the package is where a judgement can be
//  tested without a phone.
//

import Foundation
import FlowerPowerCore

public struct LiveActivityPlan: Equatable, Sendable {

    /// The three things at the hive that have a duration.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case siege
        case swarm
        case matingFlight
    }

    public struct Item: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        /// One line: what the colony is doing about it.
        public let status: String
        /// 0...1 for a progress ring, or nil when there is nothing to fill.
        public let progress: Double?
        /// The colony's posture, for display.
        public let posture: String
        /// Whether the player can still do something about it.
        public let decisionOpen: Bool
        /// Simulated days left in the event itself, for the countdown.
        public let daysRemaining: Int
        /// The simulated day on which the card has outstayed its welcome,
        /// whatever the event is still doing. The app turns this into the
        /// activity's stale date.
        public let expiresOnDay: Int
    }

    /// The longest any card stays up, in simulated days. One is about two
    /// real hours, and half that in a double-speed winter.
    public static let longestDays = 1

    public let items: [Item]

    public init(snapshot: ColonySnapshot) {
        var items: [Item] = []
        let day = snapshot.day

        // A siege, while it is new and nobody has answered it. A siege with
        // nothing to offer — a bear, a badger — still gets its card for the
        // day, because it is the most dramatic thing that happens to a colony
        // and the card is how the player hears about it.
        if let threat = snapshot.activeThreat,
           snapshot.posture == .instinct,
           day < threat.beganOnDay + Self.longestDays {
            let total = max(1, threat.resolvesOnDay - threat.beganOnDay)
            let elapsed = min(total, max(0, day - threat.beganOnDay))
            let answerable = threat.options.contains { $0 != .instinct }
            items.append(Item(
                kind: .siege,
                title: "\(threat.predator.displayName) at the nest",
                status: answerable
                    ? "The colony holds by instinct"
                    : "Nothing to be done but wait",
                progress: Double(elapsed) / Double(total),
                posture: snapshot.posture.displayName,
                decisionOpen: answerable,
                daysRemaining: threat.daysRemaining(on: day),
                expiresOnDay: threat.beganOnDay + Self.longestDays
            ))
        }

        // Swarm cells, until the player has made room or the day is out.
        if let swarm = snapshot.pendingSwarm,
           !swarm.discouraged,
           day < swarm.startedOnDay + Self.longestDays {
            let total = max(1, swarm.departsOnDay - swarm.startedOnDay)
            let elapsed = min(total, max(0, day - swarm.startedOnDay))
            items.append(Item(
                kind: .swarm,
                title: "Preparing to swarm",
                status: "Swarm cells started",
                progress: Double(elapsed) / Double(total),
                posture: snapshot.posture.displayName,
                decisionOpen: true,
                daysRemaining: swarm.daysRemaining(on: day),
                expiresOnDay: swarm.startedOnDay + Self.longestDays
            ))
        }

        // A virgin queen, on the day she emerges. There is nothing to decide,
        // and she may be a virgin for a week; the card is the announcement
        // and the dashboard carries the wait.
        if snapshot.queen.state == .virgin, snapshot.queen.ageDays < Self.longestDays {
            items.append(Item(
                kind: .matingFlight,
                title: "A virgin queen",
                status: "Waiting on her mating flight",
                progress: nil,
                posture: snapshot.posture.displayName,
                decisionOpen: false,
                daysRemaining: 0,
                expiresOnDay: day + Self.longestDays - snapshot.queen.ageDays
            ))
        }

        self.items = items
    }

    public func item(_ kind: Kind) -> Item? {
        items.first { $0.kind == kind }
    }
}
