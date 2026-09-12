//
//  AppShortcuts.swift
//  FlowerPower
//
//  The two things worth saying out loud.
//
//  App Shortcuts are the phrases Siri knows without the player building
//  anything, and they show up in the Shortcuts app under the app's name. Two
//  of them, which is the restraint the feature needs: the question, and the
//  one action that is the game. Every other intent in `AppIntents.swift` is
//  still available to a Shortcut somebody builds themselves, and belongs
//  there rather than in a phrase — "seal the entrance in FlowerPower" is a
//  thing to say for about ten days a year.
//
//  Separate from `AppIntents.swift` for a build reason rather than a tidiness
//  one. That file is compiled into the widget extension as well, so the
//  intents can be named by the widget's buttons and the Control Centre
//  control. An `AppShortcutsProvider` belongs to the app and to nothing else,
//  and a copy of one inside an extension is at best ignored.
//

import AppIntents

struct FlowerPowerShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckColonyIntent(),
            phrases: [
                "How are my bees in \(.applicationName)",
                "How is my colony in \(.applicationName)",
                "Check the hive in \(.applicationName)"
            ],
            shortTitle: "How Are My Bees",
            systemImageName: "hexagon.fill"
        )

        AppShortcut(
            intent: PhotographFlowerIntent(),
            phrases: [
                "Photograph a flower in \(.applicationName)",
                "Add a flower to \(.applicationName)"
            ],
            shortTitle: "Photograph a Flower",
            systemImageName: "camera.macro"
        )
    }
}
