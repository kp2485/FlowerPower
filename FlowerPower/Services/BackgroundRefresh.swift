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

        // `BGAppRefreshTask` is a class the SDK does not declare `Sendable`,
        // and both closures below are concurrent contexts, so the compiler
        // will not let it cross into them. Marked unsafe explicitly rather
        // than worked around, because the two calls made on it — completing
        // and completing with failure — are exactly the ones the system
        // expects from whatever queue the work finished on, and this is how
        // the code already behaved.
        nonisolated(unsafe) let task = task

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
        let report = simulation.advance(to: now)
        let after = simulation.snapshot()

        do {
            try persistence.save(simulation)
        } catch {
            logger.error("background save failed: \(error.localizedDescription)")
            return
        }

        watchLink.send(simulation, summary: simulation.watchSummary(now: now))
        await MainActor.run { LiveActivities.reconcile(with: after) }
        await notifyIfNeeded(before: before, after: after)
        await digestIfDue(report: report, snapshot: after, now: now)
    }

    // MARK: - The morning report

    private static let lastDigestKey = "lastDigestDay"

    /// One digest a day, at the hour the player chose, and only if there is
    /// something in it.
    private static func digestIfDue(report: CatchUpReport, snapshot: ColonySnapshot, now: Date) async {
        let hour = UserDefaults.standard.object(forKey: "digestHour") as? Int ?? 8
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let lastSent = UserDefaults.standard.object(forKey: lastDigestKey) as? Date

        guard calendar.component(.hour, from: now) >= hour,
              lastSent.map({ calendar.startOfDay(for: $0) < today }) ?? true
        else { return }

        // `DailyDigest` decides whether the interval was worth a word. A quiet
        // day in a steady colony is not, and is recorded as sent so it is not
        // asked again until tomorrow.
        guard let digest = DailyDigest.make(from: report, snapshot: snapshot) else {
            UserDefaults.standard.set(now, forKey: lastDigestKey)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = digest.title
        content.body = digest.body
        content.categoryIdentifier = NotificationActions.Category.digest.rawValue
        content.interruptionLevel = .passive

        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "digest", content: content, trigger: nil)
        )
        UserDefaults.standard.set(now, forKey: lastDigestKey)
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

        // A decision gets its action buttons, and the interruption level
        // that lets it through; routine news stays quiet.
        if let category = NotificationActions.category(for: news, snapshot: after) {
            content.categoryIdentifier = category.rawValue
            content.interruptionLevel = .timeSensitive
        }

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
