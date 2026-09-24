//
//  LiveActivities.swift
//  FlowerPower
//
//  Starting, updating and ending the Live Activities for things happening at
//  the hive.
//
//  Called from every catch-up, in the app and in the background task, and
//  after every decision taken from a notification or from a card's own
//  buttons. *Which* cards should be up, in which phase, until when, and what
//  the last word on each one is, are `LiveActivityPlan`'s judgements and live
//  in the package where they are tested; this file reconciles ActivityKit
//  with that plan — starts a card the plan has and the lock screen does not,
//  updates one both have, ends one the plan has dropped. Reconciliation
//  rather than event handling, because a catch-up can cover twelve simulated
//  days and an event can begin and end inside it — in which case there is
//  nothing to show and nothing is shown.
//
//  ## Why a card used to stay up far too long, and what stops it
//
//  The first player to have a skunk at the nest said the card "stayed active
//  for way too long", and it had: six real hours of siege, and then up to four
//  more, because an activity ended under the default dismissal policy is kept
//  on the lock screen for as long as iOS sees fit.
//
//  1. The plan keeps a question up for a simulated day at most, and an
//     answered siege only until it is settled — never past ActivityKit's
//     eight hours. See `LiveActivityPlan`.
//  2. Every card carries a **stale date**. The widget draws a stale card as
//     over, so even a card nothing came back to take down stops claiming that
//     something is going on.
//  3. A card whose event has not ended — a question left to instinct — is
//     ended with `.immediate`. A card whose event *has* ended is ended with
//     its outcome on it and dismissed after half an hour, which is a policy
//     the app chooses rather than the four hours iOS would.
//  4. Something comes back to take it down. While the process lives, a task
//     sleeps until the stale date and ends the card; and the background
//     refresh is asked to run no later than the soonest stale date, so a
//     suspended app gets a chance too. iOS gives an app no way to book an
//     activity's removal in advance without a push server, so that request is
//     a request — which is what the stale date is the backstop for.
//
//  ## Why the cards do not go still
//
//  The second thing the player said was that two hours of one sentence is
//  not worth two hours of lock screen. Nothing can redraw a card while the
//  app is suspended, so what moves on it is what ActivityKit moves by itself:
//  a timer and a ring counting to a real date the plan worked out. Everything
//  else is redrawn whenever the app next runs — including when a button on
//  the card is tapped, because those are `LiveActivityIntent`s and perform
//  in this process. See `ColonyIntents.onDecided`.
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

    /// How long after a holding card's stale date the sleeping task waits
    /// before taking it down itself.
    ///
    /// A holding card goes stale at the moment its siege is settled, which is
    /// also the moment the store's next catch-up reconciles and ends it with
    /// the outcome on it. The task is the backstop for when that does not
    /// happen, and it must lose that race rather than win it — a card taken
    /// down blank a second before it could have said "driven off" is the old
    /// card's fault all over again.
    private static let outcomeGrace: TimeInterval = 10 * 60

    /// Brings the running activities into line with the colony.
    ///
    /// Takes the simulation rather than the snapshot because a card needs
    /// three things the snapshot does not carry: the seasonal clock, to turn
    /// simulated days into the real dates the card counts towards; the
    /// swarm's departure share, for its estimate; and the attack history, for
    /// what a siege cost. `snapshot` is for callers that already have one.
    static func reconcile(
        with simulation: Simulation,
        snapshot: ColonySnapshot? = nil,
        now: Date = Date()
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let snapshot = snapshot ?? simulation.snapshot()
        let plan = LiveActivityPlan(simulation: simulation, now: now, snapshot: snapshot)

        // Only cards still up. An ended card stays in `activities` until it
        // is dismissed — half an hour, for one ended with its outcome — and
        // must be neither ended twice nor updated back into a countdown.
        let running = Activity<HiveActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }

        // End anything the plan no longer has. If its event is over, with the
        // last word on it; if not — a question left to instinct, a card past
        // its eight hours — at once.
        for activity in running {
            let event = subject(of: activity.attributes)
            guard plan.item(for: event) == nil else { continue }
            let id = activity.id

            if let outcome = LiveActivityPlan.outcome(
                for: event,
                in: snapshot,
                attacks: simulation.world.attackHistory,
                now: now
            ) {
                let state = contentState(outcome)
                let dismissal = outcome.staleDate
                Task { await end(id, saying: state, dismissedAt: dismissal) }
            } else {
                Task { await end(id) }
            }
        }

        // Update or start the rest.
        var booked = false
        for item in plan.items {
            let state = contentState(item)
            let grace = item.phase == .holding ? outcomeGrace : 0

            if let activity = running.first(where: { subject(of: $0.attributes) == item.event }) {
                // Only what changed. The store calls this on every tick while
                // the app is open, and an update that changes nothing is still
                // a redraw.
                let content = activity.content
                guard content.state != state || content.staleDate != item.staleDate else { continue }
                let id = activity.id
                Task { await update(id, to: state, staleDate: item.staleDate) }
                // Answering moves the stale date — from the end of the
                // question's day to the end of the siege — and the task
                // sleeping on the old one will find the card not stale yet
                // and leave it. This one is for the new date.
                if content.staleDate != item.staleDate {
                    Task { await end(id, ifStaleAt: item.staleDate, grace: grace) }
                    booked = true
                }
            } else {
                do {
                    let activity = try Activity.request(
                        attributes: HiveActivityAttributes(
                            kind: activityKind(item.kind),
                            title: item.title,
                            symbol: item.symbol,
                            startedOnDay: item.event.startedOnDay,
                            predator: item.event.predator?.rawValue
                        ),
                        content: .init(state: state, staleDate: item.staleDate),
                        pushType: nil
                    )
                    booked = true
                    let id = activity.id
                    Task { await end(id, ifStaleAt: item.staleDate, grace: grace) }
                } catch {
                    logger.debug("could not start live activity: \(error.localizedDescription)")
                }
            }
        }

        // A new card, or a card with a new stale date, has a new deadline;
        // let the background refresh know.
        if booked { BackgroundRefresh.schedule() }
    }

    /// The soonest moment any card on the lock screen goes stale, which is
    /// the latest the background refresh would like to be woken.
    nonisolated static func soonestExpiry() -> Date? {
        Activity<HiveActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
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

    /// Ends a card with its outcome on it, readable until `dismissedAt`.
    ///
    /// No stale date on the final content: an ended card is not redrawn
    /// again, and the dismissal is what takes it away.
    @concurrent
    private nonisolated static func end(
        _ id: String,
        saying state: HiveActivityAttributes.ContentState,
        dismissedAt date: Date
    ) async {
        guard let activity = Activity<HiveActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(date)
        )
    }

    /// Waits for the stale date and takes the card down, if the process lives
    /// that long. If it does not, the stale date and the background refresh
    /// are what is left.
    ///
    /// On waking it checks the card is still up and still stale. Either may
    /// have changed while it slept: the card may have been answered, which
    /// moves its stale date on, or ended with its outcome by a catch-up.
    @concurrent
    private nonisolated static func end(_ id: String, ifStaleAt date: Date, grace: TimeInterval) async {
        let wait = date.addingTimeInterval(grace).timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled else { return }
        guard let activity = Activity<HiveActivityAttributes>.activities
            .first(where: { $0.id == id }),
              activity.activityState == .active || activity.activityState == .stale,
              let staleDate = activity.content.staleDate,
              staleDate <= Date()
        else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
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
            phase: activityPhase(item.phase),
            title: item.title,
            status: item.status,
            posture: item.posture,
            decisionOpen: item.decisionOpen,
            answers: item.answers.map(\.identifier),
            startedAt: item.startedAt,
            deadline: item.deadline,
            resolvesAt: item.resolvesAt,
            guards: item.scene.guards,
            // Rounded, because it is drawn as a short bar and it decays on
            // every tick: unrounded, every catch-up would be an update that
            // changes nothing anybody could see.
            alarm: item.scene.alarm.map { ($0 * 20).rounded() / 20 },
            beesLost: item.scene.beesLost,
            storesLost: item.scene.storesLost,
            repelled: item.scene.repelled,
            departing: item.scene.departing,
            queenCells: item.scene.queenCells
        )
    }

    /// The event a card on the lock screen is about, read back from its
    /// attributes.
    private static func subject(of attributes: HiveActivityAttributes) -> LiveActivityPlan.Event {
        LiveActivityPlan.Event(
            kind: planKind(attributes.kind),
            startedOnDay: attributes.startedOnDay,
            predator: attributes.predator.flatMap(Predator.init(rawValue:))
        )
    }

    /// The plan's kinds and phases and the attributes' are the same things
    /// spelled twice, because the attributes are compiled into the widget
    /// extension and the plan into the package. Exhaustive switches keep them
    /// honest.
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

    private static func activityPhase(_ phase: LiveActivityPlan.Phase) -> HiveActivityAttributes.Phase {
        switch phase {
        case .deciding: return .deciding
        case .holding: return .holding
        case .resolved: return .resolved
        }
    }
}
