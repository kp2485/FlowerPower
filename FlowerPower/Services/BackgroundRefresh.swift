//
//  BackgroundRefresh.swift
//  FlowerPower
//
//  Keeping the colony current while the app is closed.
//
//  The engine never needed a timer: it is handed a `Date` and works out what
//  should have happened, so nothing is lost by not running. What *is* lost is
//  everything downstream of the save file. The watch reads a copy the phone
//  sends, and the complication reads a copy on the watch, so if the phone app
//  is never opened, a player's wrist shows a colony from whenever they last
//  looked at their phone. That was the gap: there was no background task and
//  no notification anywhere in the app.
//
//  So this does three things on each wake, in order of how much they matter:
//  advance the simulation, push the save to the watch, and tell the player if
//  something needs them.
//
//  Notifications are deliberately sparse. An idle game that pings about
//  nothing gets its notifications turned off, and then it cannot say the one
//  thing that matters — that the colony is about to die.
//

import Foundation
import BackgroundTasks
import UserNotifications
import FlowerPowerCore
import FlowerPowerGame
import os

enum BackgroundRefresh {

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    static let taskIdentifier = "com.kylepeterson.flowerpower.refresh"

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "background"
    )

    /// Roughly four times a day. The system decides when it actually runs,
    /// and will run it less often for a player who rarely opens the app —
    /// which is the right behaviour, not something to fight.
    private static let interval: TimeInterval = 6 * 3600

    // MARK: - Registration

    /// Called once, from the app's initialiser. Registering after the app has
    /// finished launching is too late and the system will refuse the handler.
    static func register(watchLink: WatchLink) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, watchLink: watchLink)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails in the simulator and when the player has
            // background refresh switched off. Neither is worth surfacing:
            // the game is completely playable without this.
            logger.debug("could not schedule refresh: \(error.localizedDescription)")
        }
    }

    // MARK: - Running

    private static func handle(_ task: BGAppRefreshTask, watchLink: WatchLink) {
        // Always ask for the next one first. If this one is killed part way
        // through, there is still another booked.
        schedule()

        let work = Task {
            await refresh(watchLink: watchLink)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Advances the saved colony, sends it to the watch, and notifies if
    /// something has gone wrong.
    ///
    /// Works on the save file directly rather than through `GameStore`,
    /// because the store is main-actor-bound to a running interface that does
    /// not exist here.
    static func refresh(
        watchLink: WatchLink,
        persistence: GamePersisting = GamePersistence(),
        now: Date = Date()
    ) async {
        guard var simulation = try? persistence.load() else { return }

        let before = simulation.snapshot()
        simulation.advance(to: now)
        let after = simulation.snapshot()

        do {
            try persistence.save(simulation)
        } catch {
            logger.error("background save failed: \(error.localizedDescription)")
            return
        }

        watchLink.send(simulation, summary: simulation.watchSummary(now: now))
        await notifyIfNeeded(before: before, after: after)
    }

    // MARK: - Notifications

    static func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Only on a *change* worth interrupting someone for, and only downward.
    ///
    /// The judgement itself is `ColonyNews`, in the package, so it can be
    /// tested without a notification centre. This is only the delivering.
    private static func notifyIfNeeded(
        before: ColonySnapshot,
        after: ColonySnapshot
    ) async {
        guard let news = ColonyNews.between(before: before, after: after) else { return }

        let content = UNMutableNotificationContent()
        content.title = news.title
        content.body = news.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: news.identifier,
            content: content,
            // nil trigger: deliver now. We are already running because the
            // system chose to wake us, so there is nothing to wait for.
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

}
