//
//  FlowerPowerApp.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/8/23.
//

import SwiftUI
import UserNotifications
import FlowerPowerCore
import FlowerPowerGame

@main
struct FlowerPowerApp: App {

    /// Loaded once, from the App Group container the watch app and the widget
    /// extension on this device also read.
    @State private var store = GameStore.load()

    /// Keeps the watch's copy in step whenever the colony changes.
    ///
    /// Declared without a default and assigned in `init`, deliberately: a
    /// default value here would be built *and then thrown away* when `init`
    /// assigns over it, and since `WatchLink` makes itself the `WCSession`
    /// delegate on construction, the discarded one would have already taken
    /// the delegate slot from the one actually being used.
    @State private var watchLink: WatchLink

    /// Receives tapped notification actions. Held for the app's lifetime,
    /// because the notification centre keeps only a weak reference.
    private let notifications = NotificationDelegate()

    /// An action that needs the interface — following a swarm needs a site
    /// chosen — arrives here and is handed to the content view.
    @State private var requestedAction: String?

    init() {
        // Background task handlers must be registered before launch finishes,
        // so this cannot wait for a view to appear. The link is built here for
        // the same reason: `WatchLink` is what the background task hands the
        // colony to, and it needs to exist by the time one fires.
        let link = WatchLink()
        _watchLink = State(initialValue: link)
        BackgroundRefresh.register(watchLink: link)

        // Decisions arrive as notifications with action buttons. The
        // categories those buttons live in have to exist before one is
        // delivered.
        NotificationActions.register()
        UNUserNotificationCenter.current().delegate = notifications

        // Contextual tips. Must be configured before any `TipView` is drawn.
        Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onChange(of: store.snapshot) { _, snapshot in
                    watchLink.send(
                        store.simulationForTransfer,
                        summary: store.watchSummary()
                    )
                    LiveActivities.reconcile(with: snapshot)
                    HiveHum.shared.update(for: snapshot)
                }
                .onAppear {
                    notifications.onOpenApp = { action in
                        requestedAction = action
                    }
                    // An App Intent that needs the interface — photographing
                    // a flower — arrives down the same channel.
                    AppIntentRequests.onOpenApp = { action in
                        requestedAction = action
                    }
                    // So a decision answered on the watch goes through the
                    // store the player is looking at rather than behind its
                    // back. See `WatchLink.store`.
                    watchLink.store = store
                }
                .environment(\.requestedAction, requestedAction)
                // Notification permission is not asked for here any more. A
                // `.task` on the root view fires before the first frame, so
                // the system prompt was the opening screen of the app with
                // nothing behind it to explain why — and iOS gives an app
                // exactly one chance to ask. It is now the last page of
                // `OnboardingView`, after the page that says the colony makes
                // decisions while the app is closed.
        }
    }
}

// MARK: - An action waiting on the interface

private struct RequestedActionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// A notification action that could not be completed from the lock
    /// screen because it needs something chosen — a site for a swarm.
    var requestedAction: String? {
        get { self[RequestedActionKey.self] }
        set { self[RequestedActionKey.self] = newValue }
    }
}
