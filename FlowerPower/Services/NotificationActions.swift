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
//  What the buttons are spelled with, and what a tapped one does, both live in
//  the package now, as `DecisionAction` and `GameStore.apply(_:)`. The watch
//  needs the same vocabulary and cannot see this file; and the switch that
//  turned an identifier into a change to the colony was an exhaustive switch
//  over engine types written somewhere no compiler on this machine could check
//  it. All that is left here is the notification centre: which categories
//  exist, which buttons they carry, and which piece of news belongs in which.
//
//  What arrives here is the player's own choice on their own device, so it is
//  not treated as untrusted. What it is treated as is possibly stale: a
//  notification can sit on the lock screen for hours, and by the time it is
//  tapped the siege may be over. `GameStore.apply(_:)` checks the decision is
//  still open and does nothing rather than something wrong if it is not.
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
        case nestFull = "nest.full"
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

    /// The one action that is not a `DecisionAction`.
    ///
    /// Following a swarm needs a site chosen, and a site cannot be chosen from
    /// a lock screen, so this button opens the app and is answered there.
    /// Every other identifier is `DecisionAction.identifier`.
    enum Action {
        static let followSwarm = "swarm.follow"
    }

    /// A button for an answer, with the answer's own words on it.
    private static func button(
        _ action: DecisionAction,
        options: UNNotificationActionOptions = []
    ) -> UNNotificationAction {
        UNNotificationAction(
            identifier: action.identifier,
            title: action.title,
            options: options
        )
    }

    /// Registers every category once. Called at launch.
    static func register() {
        var categories = Set<UNNotificationCategory>()

        for style in [AttackStyle.entrance, .pilfer, .field, .comb] {
            guard let category = Category.forThreat(style) else { continue }
            let actions = HivePosture.options(against: style)
                .filter { $0 != .instinct }
                .map { button(.posture($0)) }
            categories.insert(UNNotificationCategory(
                identifier: category.rawValue,
                actions: actions,
                intentIdentifiers: [],
                options: []
            ))
        }

        // Ordered by what the measurement actually says, which is not the
        // order they were built in. Over 200 colonies across two years,
        // two-year survival is 76% for making room, 66% for doing nothing at
        // all, 62% for adding comb and 56% for dividing. Talking them out of
        // it is the best answer there is, so it goes first.
        //
        // Adding comb was briefly the only thing offered here, and dropping
        // "Make Room" from the list quietly removed the most valuable option
        // the player had.
        categories.insert(UNNotificationCategory(
            identifier: Category.swarmPreparing.rawValue,
            actions: [
                button(.discourageSwarm),
                button(.addComb),
                button(.split),
                button(.letSwarmGo)
            ],
            intentIdentifiers: [], options: []
        ))

        // The week before the cells, when space is still cheap.
        categories.insert(UNNotificationCategory(
            identifier: Category.nestFull.rawValue,
            actions: [button(.addComb)],
            intentIdentifiers: [], options: []
        ))

        categories.insert(UNNotificationCategory(
            identifier: Category.swarmDeparted.rawValue,
            actions: [
                // Following needs a site chosen, so it opens the app.
                UNNotificationAction(identifier: Action.followSwarm, title: "Follow the Swarm",
                                     options: [.foreground]),
                button(.staySwarm)
            ],
            intentIdentifiers: [], options: []
        ))

        categories.insert(UNNotificationCategory(
            identifier: Category.entrance.rawValue,
            actions: [button(.sealEntrance), button(.openEntrance)],
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
        if news.identifier.hasPrefix("nest-full-") {
            // Nothing to offer where the site has no more room to give, and an
            // action button that does nothing is worse than no button.
            return snapshot.canAddComb ? .nestFull : nil
        }
        if news.identifier.hasPrefix("departed-") { return .swarmDeparted }
        if news.identifier.hasPrefix("entrance-") { return .entrance }
        return nil
    }

    // MARK: - Handling

    /// Turns a tapped action into a change to the colony.
    ///
    /// Works on the save file rather than on the app's own store, because a
    /// notification action can arrive with no interface running at all — and
    /// through a store built around that file rather than by reaching into the
    /// simulation, so a decision answered from the lock screen takes exactly
    /// the path a button in the app takes, saving as it goes.
    ///
    /// The store is main-actor-bound, which is why this is. That is not the
    /// same thing as needing an interface: the main actor exists in an app
    /// woken in the background, and nothing here touches a view.
    ///
    /// A store the player is actually looking at is a different matter: it
    /// holds its own copy of the colony and will overwrite this one from that
    /// copy on its next catch-up, taking the decision with it. That is the
    /// usual case for a tap on the watch, which is why `WatchLink` goes
    /// through the running store when there is one. It is the unusual case
    /// here — a button tapped from the notification centre with the app
    /// already open — and it is not handled, as it was not before.
    @MainActor
    static func handle(
        actionIdentifier: String,
        persistence: GamePersisting = GamePersistence(),
        now: Date = Date()
    ) -> Bool {
        guard let action = DecisionAction(identifier: actionIdentifier) else { return false }
        // `try?` flattens, so one binding covers both "it would not read" and
        // "there is nothing saved".
        guard let simulation = try? persistence.load() else { return false }

        let store = GameStore(simulation: simulation, persistence: persistence, clock: { now })
        // The tap may be hours old, and the decision has to be judged against
        // the colony as it is now rather than as it was when the notification
        // was written.
        store.catchUp()

        let applied = store.apply(action)
        if let error = store.lastError {
            logger.error("could not save a decision: \(error)")
            return false
        }
        return applied
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
            // With a nonce, for the same reason `PhotographFlowerIntent`
            // carries one: the interface reacts to the value *changing*, and
            // the second tap of the same button in one session would
            // otherwise look like no request at all.
            await MainActor.run { self.onOpenApp?(action + "#" + UUID().uuidString) }
            return
        }
        // On the main actor because the store is, and on the save file because
        // there may be no interface running at all. Those are not in tension:
        // see `handle(actionIdentifier:persistence:now:)`.
        _ = await NotificationActions.handle(actionIdentifier: action)
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
