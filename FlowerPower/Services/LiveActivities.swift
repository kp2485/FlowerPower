//
//  LiveActivities.swift
//  FlowerPower
//
//  Starting, updating and ending the Live Activities for things happening at
//  the hive.
//
//  Called from every catch-up, in the app and in the background task, with
//  the snapshot after it. *Which* cards should be up, and for how long, is
//  `LiveActivityPlan`'s judgement and lives in the package where it is tested;
//  this file reconciles ActivityKit with that plan — starts a card the plan
//  has and the lock screen does not, updates one both have, ends one the plan
//  has dropped. Reconciliation rather than event handling, because a catch-up
//  can cover twelve simulated days and an event can begin and end inside it —
//  in which case there is nothing to show and nothing is shown.
//
//  ## Why a card used to stay up far too long, and the four things that stop it
//
//  The first player to have a skunk at the nest said the card "stayed active
//  for way too long", and it had: six real hours of siege, and then up to four
//  more, because an activity ended under the default dismissal policy is kept
//  on the lock screen for as long as iOS sees fit.
//
//  1. The plan only keeps a card while there is something to decide, and
//     never for more than a simulated day. See `LiveActivityPlan`.
//  2. Every card carries a **stale date** — the real instant that simulated
//     day runs out. The widget draws a stale card as finished, so even a card
//     nothing came back to take down stops claiming that something is going
//     on.
//  3. A card is ended with `.immediate`, not `.default`. When it is over it
//     is gone.
//  4. Something comes back to take it down. While the process lives, a task
//     sleeps until the stale date and ends the card; and the background
//     refresh is asked to run no later than the soonest stale date, so a
//     suspended app gets a chance too. iOS gives an app no way to book an
//     activity's removal in advance without a push server, so that request is
//     a request — which is what the stale date is the backstop for.
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
    ///
    /// `dateAfterDays` turns a number of simulated days from now into the real
    /// instant they begin. It is a parameter because the seasonal clock is the
    /// simulation's business and the snapshot does not carry it: the app asks
    /// its store, and the background task asks the simulation it has just
    /// advanced.
    static func reconcile(
        with snapshot: ColonySnapshot,
        dateAfterDays: (Int) -> Date
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let plan = LiveActivityPlan(snapshot: snapshot)
        let running = Activity<HiveActivityAttributes>.activities

        // End anything the plan no longer has — answered, over, or simply up
        // for long enough.
        for activity in running
        where plan.item(planKind(activity.attributes.kind)) == nil {
            let id = activity.id
            Task { await end(id) }
        }

        // Update or start the rest.
        var started = false
        for item in plan.items {
            let kind = activityKind(item.kind)
            let state = contentState(item)
            let staleDate = dateAfterDays(max(0, item.expiresOnDay - snapshot.day))

            if let activity = running.first(where: { $0.attributes.kind == kind }) {
                let id = activity.id
                Task { await update(id, to: state, staleDate: staleDate) }
            } else {
                do {
                    let activity = try Activity.request(
                        attributes: HiveActivityAttributes(
                            kind: kind,
                            title: item.title,
                            symbol: symbol(item.kind)
                        ),
                        content: .init(state: state, staleDate: staleDate),
                        pushType: nil
                    )
                    started = true
                    let id = activity.id
                    Task { await end(id, at: staleDate) }
                } catch {
                    logger.debug("could not start live activity: \(error.localizedDescription)")
                }
            }
        }

        // A new card has a new deadline; let the background refresh know.
        if started { BackgroundRefresh.schedule() }
    }

    /// The soonest moment any card on the lock screen goes stale, which is
    /// the latest the background refresh would like to be woken.
    nonisolated static func soonestExpiry() -> Date? {
        Activity<HiveActivityAttributes>.activities
            .compactMap(\.content.staleDate)
            .min()
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
        // Immediately. The default policy keeps an ended card on the lock
        // screen for up to four hours, which is how a six-hour siege became
        // a ten-hour card.
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// Waits for the stale date and takes the card down, if the process lives
    /// that long. If it does not, the stale date and the background refresh
    /// are what is left.
    @concurrent
    private nonisolated static func end(_ id: String, at date: Date) async {
        let wait = date.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled else { return }
        await end(id)
    }

    @concurrent
    private nonisolated static func update(
        _ id: String,
        to state: HiveActivityAttributes.ContentState,
        staleDate: Date
    ) async {
        guard let activity = Activity<HiveActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: staleDate))
    }

    // MARK: - Between the plan and ActivityKit

    private static func contentState(
        _ item: LiveActivityPlan.Item
    ) -> HiveActivityAttributes.ContentState {
        .init(
            status: item.status,
            progress: item.progress,
            posture: item.posture,
            decisionOpen: item.decisionOpen,
            daysRemaining: item.daysRemaining
        )
    }

    /// The plan's kinds and the attributes' kinds are the same three things
    /// spelled twice, because the attributes are compiled into the widget
    /// extension and the plan into the package. Two exhaustive switches keep
    /// them honest.
    private static func activityKind(_ kind: LiveActivityPlan.Kind) -> HiveActivityAttributes.Kind {
        switch kind {
        case .siege: return .siege
        case .swarm: return .swarm
        case .matingFlight: return .matingFlight
        }
    }

    private static func planKind(_ kind: HiveActivityAttributes.Kind) -> LiveActivityPlan.Kind {
        switch kind {
        case .siege: return .siege
        case .swarm: return .swarm
        case .matingFlight: return .matingFlight
        }
    }

    private static func symbol(_ kind: LiveActivityPlan.Kind) -> String {
        switch kind {
        case .siege: return "exclamationmark.shield.fill"
        case .swarm: return "arrow.triangle.branch"
        case .matingFlight: return "crown.fill"
        }
    }
}
