//
//  HiveActivityAttributes.swift
//  FlowerPowerWidgets
//
//  What a Live Activity shows while something is happening at the hive.
//
//  Three things at the hive have a duration, and each is what Live Activities
//  are for: a siege under way, a swarm gathering, and a queen out on her
//  mating flight. The attributes are the part that does not change for the
//  life of the activity; the content state is what the background task
//  updates as the event runs.
//
//  Shared between the app, which starts and updates activities, and the
//  widget extension, which draws them. It is in the widget folder and
//  compiled into both targets.
//

import Foundation
import ActivityKit

struct HiveActivityAttributes: ActivityAttributes {

    enum Kind: String, Codable, Hashable {
        case siege
        case swarm
        case matingFlight
    }

    struct ContentState: Codable, Hashable {
        /// One line: "Guards holding", "Departs in 3 days", "Out since dawn".
        var status: String
        /// 0...1 for a progress ring, or nil when there is nothing to fill.
        var progress: Double?
        /// The colony's posture, so a decision already made shows as made.
        var posture: String
        /// Whether the player can still do something about it.
        var decisionOpen: Bool
        /// Simulated days left, for the countdown.
        var daysRemaining: Int
    }

    let kind: Kind
    let title: String
    /// SF Symbol for the kind of thing.
    let symbol: String
}
