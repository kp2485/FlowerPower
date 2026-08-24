//
//  FlowerPowerWatchApp.swift
//  FlowerPower Watch
//
//  The watch has no camera, so it cannot do the thing the game is about. What
//  it can do is tell you, in the second and a half you look at it, whether the
//  colony needs you — and that turns out to be most of the value.
//

import SwiftUI
import FlowerPowerCore

@main
struct FlowerPowerWatchApp: App {

    @State private var model = WatchColonyModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
        }
    }
}
