//
//  HiveActivityAttributes.swift
//  FlowerPowerWidgets
//
//  What a Live Activity shows while something is happening at the hive.
//
//  Three things at the hive have a duration, and each is what Live Activities
//  are for: a siege under way, a swarm gathering, and a queen out on her
//  mating flight. The attributes are the part that does not change for the
//  life of the activity — including which event it is about — and the content
//  state is what the app updates as the event runs.
//
//  ActivityKit cannot redraw a card while the app is suspended, and there is
//  no push server. So everything here that changes over the card's life is a
//  `Date` the widget counts towards on its own: `deadline` for the question,
//  `resolvesAt` for the answer. Everything else is what was true the last
//  time the app ran. See `LiveActivityPlan` for which dates, and why.
//
//  Shared between the app, which starts and updates activities, and the
//  widget extension, which draws them. It is in the widget folder and
//  compiled into both targets. Plain values only — strings, numbers, dates —
//  so that the one file compiled into both does not need the package's types
//  to be `Codable` in the shape ActivityKit stores them.
//

import Foundation
import ActivityKit

struct HiveActivityAttributes: ActivityAttributes {

    enum Kind: String, Codable, Hashable {
        case siege
        case swarm
        case matingFlight
    }

    /// `LiveActivityPlan.Phase`, spelled again for the same reason `Kind` is.
    enum Phase: String, Codable, Hashable {
        /// A question is open; the answers are on the card.
        case deciding
        /// Answered, or nothing to answer; the card counts down to the end.
        case holding
        /// Over. The card says how, for half an hour.
        case resolved
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// The headline. It changes when the event ends — "Skunk driven off" —
        /// which is why it is here and not only in the attributes.
        var title: String
        /// One line: what the colony is doing about it, or how it ended.
        var status: String
        /// The colony's posture, for display.
        var posture: String
        /// Whether the player can still do something about it.
        var decisionOpen: Bool
        /// `DecisionAction.identifier` for each button, in order. Identifiers
        /// rather than the actions themselves, so this file needs nothing
        /// from the package; `AnswerButton` turns them back.
        var answers: [String]

        /// When the event began. Where the ring starts.
        var startedAt: Date
        /// When instinct answers for the player.
        var deadline: Date
        /// When the siege or swarm is settled.
        var resolvesAt: Date

        // The scene. Each kind of event fills the ones it has.

        /// Bees on guard duty.
        var guards: Int?
        /// Alarm pheromone, 0...1.
        var alarm: Double?
        /// Bees who died in the siege, once it is settled.
        var beesLost: Int?
        /// Honey taken, once it is settled.
        var storesLost: Double?
        /// Whether the attacker was driven off.
        var repelled: Bool?
        /// About how many bees would go with the swarm, or did.
        var departing: Int?
        /// Queen cells in the comb.
        var queenCells: Int?
    }

    let kind: Kind
    let title: String
    /// SF Symbol for the kind of thing — for a siege, the way the attacker
    /// comes in.
    let symbol: String
    /// Which event this card is about: `LiveActivityPlan.Event`, in plain
    /// values. A card is matched to the plan by these rather than by kind, so
    /// a skunk's card is never relabelled as the wasp's that followed it.
    let startedOnDay: Int
    /// `Predator.rawValue`, for a siege.
    let predator: String?
}
