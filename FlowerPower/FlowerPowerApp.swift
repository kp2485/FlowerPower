//
//  FlowerPowerApp.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/8/23.
//

import SwiftUI
import FlowerPowerCore

@main
struct FlowerPowerApp: App {

    /// Loaded once, from the shared App Group container the watch also reads.
    @State private var store = GameStore.load()

    /// Keeps the watch's copy in step whenever the colony changes.
    @State private var watchLink = WatchLink()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onChange(of: store.snapshot) { _, _ in
                    watchLink.send(store.watchSummary())
                }
        }
    }
}
