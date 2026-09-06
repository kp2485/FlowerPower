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
        subsystem: "com.kylepeterson.flowerpower",
        category: "liveActivities"
    )

    /// Brings the running activities into line with the snapshot.
    static func reconcile(with snapshot: ColonySnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let wanted = desired(for: snapshot)
        let running = Activity<HiveActivityAttributes>.activities

        // End anything no longer happening.
        for activity in running where wanted[activity.attributes.kind] == nil {
            Task { await activity.end(nil, dismissalPolicy: .default) }
        }

        // Update or start the rest.
        for (kind, item) in wanted {
            if let activity = running.first(where: { $0.attributes.kind == kind }) {
                Task { await activity.update(.init(state: item.state, staleDate: nil)) }
            } else {
                do {
                    _ = try Activity.request(
                        attributes: item.attributes,
                        content: .init(state: item.state, staleDate: nil),
                        pushType: nil
                    )
                } catch {
                    logger.debug("could not start live activity: \(error.localizedDescription)")
                }
            }
        }
    }

    private struct Item {
        let attributes: HiveActivityAttributes
        let state: HiveActivityAttributes.ContentState
    }

    private static func desired(
        for snapshot: ColonySnapshot
    ) -> [HiveActivityAttributes.Kind: Item] {
        var items: [HiveActivityAttributes.Kind: Item] = [:]

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
                    status: snapshot.posture == .instinct
                        ? "The colony holds by instinct"
                        : "Holding: \(snapshot.posture.displayName)",
                    progress: Double(elapsed) / Double(total),
                    posture: snapshot.posture.displayName,
                    decisionOpen: snapshot.posture == .instinct,
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
                    status: swarm.discouraged ? "Making room; they may still go" : "Swarm cells capped",
                    progress: Double(elapsed) / Double(total),
                    posture: snapshot.posture.displayName,
                    decisionOpen: !swarm.discouraged,
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
