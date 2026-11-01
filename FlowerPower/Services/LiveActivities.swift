//
//  LiveActivities.swift
//  FlowerPower
//
//  Starting, updating and ending the Live Activities for things happening at
//  the hive.
//
//  Called from every catch-up, in the app and in the background task, with
//  the snapshot before and after. It works out which of the three durational
//  events are running, and reconciles: starts one that has begun, updates one
//  that is still going, ends one that has finished. Reconciliation rather
//  than event handling, because a catch-up can cover twelve simulated days
//  and an event can begin and end inside it — in which case there is nothing
//  to show and nothing is shown.
//

import Foundation
import ActivityKit
import FlowerPowerCore
import FlowerPowerGame
import os

@MainActor
enum LiveActivities {

    private static let logger = Logger(
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "liveActivities"
    )

    /// Brings the running activities into line with the snapshot.
    static func reconcile(with snapshot: ColonySnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let wanted = desired(for: snapshot)
        // Ended activities stay in this list until they are dismissed, which
        // can be hours. Counting them found an ended siege to "update", and a
        // new siege of the same kind in that time got no activity at all.
        let running = Activity<HiveActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }

        // End anything no longer happening.
        for activity in running where wanted[activity.attributes.kind] == nil {
            let id = activity.id
            Task { await end(id) }
        }

        // Update or start the rest.
        for (kind, item) in wanted {
            if let activity = running.first(where: { $0.attributes.kind == kind }) {
                // The title is fixed for an activity's life, so a hornet
                // arriving as a wasp left needs one of its own.
                if activity.attributes.title != item.attributes.title {
                    let id = activity.id
                    Task { await end(id) }
                    start(item)
                    continue
                }
                // This runs on every live tick; most of them change nothing.
                guard activity.content.state != item.state else { continue }
                let id = activity.id
                let state = item.state
                Task { await update(id, to: state) }
            } else {
                start(item)
            }
        }
    }

    private static func start(_ item: Item) {
        do {
            _ = try Activity.request(
                attributes: item.attributes,
                content: .init(state: item.state, staleDate: staleDate()),
                pushType: nil
            )
        } catch {
            logger.debug("could not start live activity: \(error.localizedDescription)")
        }
    }

    /// When what is on the lock screen stops being trustworthy.
    ///
    /// Its countdown is in simulated days and only moves while the app or a
    /// background wake runs, so "2d" could sit there for hours being wrong
    /// with nothing to say so. A simulated day is two real hours; past that
    /// the system dims it as out of date.
    nonisolated private static func staleDate() -> Date {
        Date().addingTimeInterval(2.5 * 3600)
    }

    // MARK: - Off the main actor

    /// `Activity` is not `Sendable`, and ending or updating one runs off the
    /// main actor, so an activity found in `reconcile` cannot be carried into
    /// either. Its identifier can, and the activity is found again on this
    /// side — where it never crosses an isolation boundary at all.
    @concurrent
    private nonisolated static func end(_ id: String) async {
        guard let activity = Activity<HiveActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        // At once: `.default` left the last "holds by instinct, 2d" sitting on
        // the lock screen for hours after the siege it described had ended.
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    @concurrent
    private nonisolated static func update(
        _ id: String,
        to state: HiveActivityAttributes.ContentState
    ) async {
        guard let activity = Activity<HiveActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: staleDate()))
    }

    private struct Item {
        let attributes: HiveActivityAttributes
        let state: HiveActivityAttributes.ContentState
    }

    private static func desired(
        for snapshot: ColonySnapshot
    ) -> [HiveActivityAttributes.Kind: Item] {
        var items: [HiveActivityAttributes.Kind: Item] = [:]

        // A virgin queen can outlive the rest of a dead colony, and a siege
        // can stay on the record. Neither is worth a place on the lock screen.
        guard snapshot.status.isAlive else { return items }

        if let threat = snapshot.activeThreat {
            let total = max(1, threat.resolvesOnDay - threat.beganOnDay)
            let elapsed = min(total, snapshot.day - threat.beganOnDay)
            items[.siege] = Item(
                attributes: HiveActivityAttributes(
                    kind: .siege,
                    title: "\(threat.predator.displayName) at the nest",
                    symbol: "exclamationmark.shield.fill"
                ),
                state: .init(
                    status: threat.isAnswered(by: snapshot.posture)
                        ? "Holding: \(snapshot.posture.displayName)"
                        : "The colony holds by instinct",
                    progress: Double(elapsed) / Double(total),
                    posture: snapshot.posture.displayName,
                    decisionOpen: !threat.isAnswered(by: snapshot.posture),
                    daysRemaining: threat.daysRemaining(on: snapshot.day)
                )
            )
        }

        if let swarm = snapshot.pendingSwarm {
            let total = max(1, swarm.departsOnDay - swarm.startedOnDay)
            let elapsed = min(total, snapshot.day - swarm.startedOnDay)
            items[.swarm] = Item(
                attributes: HiveActivityAttributes(
                    kind: .swarm,
                    title: "Preparing to swarm",
                    symbol: "arrow.triangle.branch"
                ),
                state: .init(
                    status: swarm.discouraged
                        ? "Making room; they may still go"
                        : swarm.isAnswered ? "You are letting them go" : "Swarm cells capped",
                    progress: Double(elapsed) / Double(total),
                    posture: snapshot.posture.displayName,
                    decisionOpen: !swarm.isAnswered,
                    daysRemaining: swarm.daysRemaining(on: snapshot.day)
                )
            )
        }

        if snapshot.queen.state == .virgin {
            items[.matingFlight] = Item(
                attributes: HiveActivityAttributes(
                    kind: .matingFlight,
                    title: "A virgin queen",
                    symbol: "crown.fill"
                ),
                state: .init(
                    status: "Waiting on her mating flight",
                    progress: nil,
                    posture: snapshot.posture.displayName,
                    decisionOpen: false,
                    daysRemaining: 0
                )
            )
        }

        return items
    }
}
