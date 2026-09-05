//
//  FlowerPowerApp.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/8/23.
//

import SwiftUI
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

    init() {
        // Background task handlers must be registered before launch finishes,
        // so this cannot wait for a view to appear. The link is built here for
        // the same reason: `WatchLink` is what the background task hands the
        // colony to, and it needs to exist by the time one fires.
        let link = WatchLink()
        _watchLink = State(initialValue: link)
        BackgroundRefresh.register(watchLink: link)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onChange(of: store.snapshot) { _, _ in
                    watchLink.send(
                        store.simulationForTransfer,
                        summary: store.watchSummary()
                    )
                }
                .task {
                    // Asked for on first run rather than at launch, so the
                    // prompt lands after the player has seen what the app is.
                    await BackgroundRefresh.requestNotificationPermission()
                }
        }
    }
}
