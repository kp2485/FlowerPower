//
//  NotificationActions.swift
//  FlowerPower
//
//  Deciding from the lock screen.
//
//  The whole point of the decision events is that they fit in a notification's
//  action buttons. "Hold the entrance" is a tap on the lock screen, or on the
//  watch, and the app never has to be opened. This registers the categories
//  those buttons live in, and turns a tapped button back into a store call.
//
//  What arrives here is the player's own choice on their own device, so it is
//  not treated as untrusted. What it is treated as is possibly stale: a
//  notification can sit on the lock screen for hours, and by the time it is
//  tapped the siege may be over. Every handler checks the decision is still
//  open before acting, and does nothing rather than something wrong if it
//  is not.
//

import Foundation
import UserNotifications
import FlowerPowerCore
import FlowerPowerGame
import os

enum NotificationActions {

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "notifications"
    )

    // MARK: - Categories

    enum Category: String, CaseIterable {
        case threatEntrance = "threat.entrance"
        case threatPilfer = "threat.pilfer"
        case threatField = "threat.field"
        case threatComb = "threat.comb"
        case swarmPreparing = "swarm.preparing"
        case swarmDeparted = "swarm.departed"
        case entrance = "entrance.autumn"
        case digest = "digest"

        static func forThreat(_ style: AttackStyle) -> Category? {
            switch style {
            case .entrance: return .threatEntrance
            case .pilfer: return .threatPilfer
            case .field: return .threatField
            case .comb: return .threatComb
            case .catastrophic, .parasite: return nil
            }
        }
    }

    /// Action identifiers carry the posture or the choice in their suffix,
    /// so one handler serves every category.
    enum Action {
        static let posturePrefix = "posture."
        static let discourageSwarm = "swarm.discourage"
        static let letSwarmGo = "swarm.let"
        static let followSwarm = "swarm.follow"
        static let staySwarm = "swarm.stay"
        static let sealEntrance = "entrance.seal"
        static let openEntrance = "entrance.open"
    }

    /// Registers every category once. Called at launch.
    static func register() {
        var categories = Set<UNNotificationCategory>()

        for style in [AttackStyle.entrance, .pilfer, .field, .comb] {
            guard let category = Category.forThreat(style) else { continue }
            let actions = HivePosture.options(against: style)
                .filter { $0 != .instinct }
                .map { posture in
                    UNNotificationAction(
                        identifier: Action.posturePrefix + posture.rawValue,
                        title: posture.displayName,
                        options: []
                    )
                }
            categories.insert(UNNotificationCategory(
                identifier: category.rawValue,
                actions: actions,
                intentIdentifiers: [],
                options: []
            ))
        }

        categories.insert(UNNotificationCategory(
            identifier: Category.swarmPreparing.rawValue,
            actions: [
                UNNotificationAction(identifier: Action.discourageSwarm, title: "Make Room", options: []),
                UNNotificationAction(identifier: Action.letSwarmGo, title: "Let Them Go", options: [])
            ],
            intentIdentifiers: [], options: []
        ))

        categories.insert(UNNotificationCategory(
            identifier: Category.swarmDeparted.rawValue,
            actions: [
                // Following needs a site chosen, so it opens the app.
                UNNotificationAction(identifier: Action.followSwarm, title: "Follow the Swarm",
                                     options: [.foreground]),
                UNNotificationAction(identifier: Action.staySwarm, title: "Stay", options: [])
            ],
            intentIdentifiers: [], options: []
        ))

        categories.insert(UNNotificationCategory(
            identifier: Category.entrance.rawValue,
            actions: [
                UNNotificationAction(identifier: Action.sealEntrance, title: "Seal It", options: []),
                UNNotificationAction(identifier: Action.openEntrance, title: "Keep It Open", options: [])
            ],
            intentIdentifiers: [], options: []
        ))

        categories.insert(UNNotificationCategory(
            identifier: Category.digest.rawValue, actions: [],
            intentIdentifiers: [], options: []
        ))

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Which category a piece of news belongs in, from its identifier.
    static func category(for news: ColonyNews, snapshot: ColonySnapshot) -> Category? {
        if news.identifier.hasPrefix("threat-"), let threat = snapshot.activeThreat {
            return Category.forThreat(threat.style)
        }
        if news.identifier.hasPrefix("swarm-") { return .swarmPreparing }
        if news.identifier.hasPrefix("departed-") { return .swarmDeparted }
        if news.identifier.hasPrefix("entrance-") { return .entrance }
        return nil
    }

    // MARK: - Handling

    /// Turns a tapped action into a change to the colony.
    ///
    /// Runs on the save file directly, because a notification action can
    /// arrive with no interface running. The store, if there is one, picks
    /// the change up on its next catch-up.
    static func handle(
        actionIdentifier: String,
        persistence: GamePersisting = GamePersistence(),
        now: Date = Date()
    ) -> Bool {
        guard var simulation = try? persistence.load() else { return false }
        simulation.advance(to: now)

        var changed = true
        switch actionIdentifier {
        case let id where id.hasPrefix(Action.posturePrefix):
            guard let posture = HivePosture(rawValue: String(id.dropFirst(Action.posturePrefix.count))),
                  let threat = simulation.world.activeThreat
            else { return false }
            simulation.respond(to: threat, with: posture)

        case Action.discourageSwarm:
            guard simulation.world.pendingSwarm != nil else { return false }
            simulation.discourageSwarm()

        case Action.letSwarmGo:
            changed = false

        case Action.staySwarm:
            simulation.forgetLastSwarm()

        case Action.sealEntrance:
            simulation.decideEntrance(sealed: true)

        case Action.openEntrance:
            simulation.decideEntrance(sealed: false)

        default:
            return false
        }

        guard changed else { return true }
        do {
            try persistence.save(simulation)
            return true
        } catch {
            logger.error("could not save a decision: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Delegate

/// Receives tapped actions. Held by the app for its lifetime.
///
/// Notification callbacks arrive from the system on no particular queue, so
/// this cannot be a `@MainActor` class; but the one thing it holds is a
/// closure that runs on the main actor, and the delegate itself has to be
/// shared with the notification centre. So: the whole object is declared
/// `Sendable` and its only mutable state is pinned to the main actor, which
/// is both what the compiler needs and what is actually true.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// Called when an action needs the interface — following a swarm needs a
    /// site chosen.
    @MainActor var onOpenApp: (@MainActor @Sendable (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        if action == NotificationActions.Action.followSwarm
            || action == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.onOpenApp?(action) }
            return
        }
        // Deliberately not on the main actor: this reads and writes the save
        // file, and there may be no interface running at all.
        _ = NotificationActions.handle(actionIdentifier: action)
    }

    /// Show decisions even while the app is in the foreground; the in-app
    /// sheet handles them too, but the banner is what says a window opened.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
