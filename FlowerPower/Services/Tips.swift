//
//  Tips.swift
//  FlowerPower
//
//  The five things the introduction cannot say.
//
//  `OnboardingView` explains what the game is, once, before the player has
//  seen any of it. That is the right place for the premise and the wrong place
//  for anything specific: a list of what each of the four tabs does, read
//  before any of them exists, is a list nobody remembers. So the specifics
//  wait until the player is standing in front of the thing — TipKit's whole
//  purpose — and each one appears next to the control it is about.
//
//  Five, and not one more. Every tip is an interruption, and the fastest way
//  to have all of them ignored is to write a sixth about something the player
//  could have worked out.
//
//  A note on the name. This enum is called `Tips` because that is what it is,
//  which means it shadows TipKit's own `Tips` inside this module — so the one
//  call that needs TipKit's version spells it `TipKit.Tips.configure`. Worth
//  the small awkwardness: every call site in the app reads `Tips.forage`.
//

import Foundation
import SwiftUI
import TipKit
import os

enum Tips {

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "tips"
    )

    // MARK: - The tips

    /// The one tip that has to land, because a colony with nothing to fly to
    /// starves however well it is run, and the camera button is the only way
    /// to fix that.
    static let photograph = PhotographTip()
    static let nest = NestTip()
    static let forage = ForageTip()
    static let garden = GardenTip()
    static let settings = SettingsTip()

    // MARK: - Setting up

    /// Called once at launch, from `FlowerPowerApp.init`.
    ///
    /// `displayFrequency(.daily)` rather than `.immediate`, deliberately: a
    /// player who explores all four tabs in their first minute would otherwise
    /// get four popovers in that minute, having just read three pages of
    /// introduction. One a day means the camera tip lands on the tab the app
    /// opens on, and the rest arrive on later visits, each still next to the
    /// thing it describes. A tip stays eligible until it is dismissed, so
    /// spacing them out does not lose any of them.
    static func configure() {
        do {
            try TipKit.Tips.configure([
                .displayFrequency(.daily),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            // Tips are the least important thing in the app. A datastore that
            // will not open is worth a log line and nothing else.
            logger.debug("could not configure tips: \(error.localizedDescription)")
        }
    }
}

// MARK: - Definitions

struct PhotographTip: Tip {
    var title: Text { Text("Photograph a flower") }
    var message: Text? {
        Text("Photographs are the only forage your bees have. Anything actually in bloom will do — the closer to the nest, the less the flight costs them.")
    }
    var image: Image? { Image(systemName: "camera.fill") }
}

struct NestTip: Tip {
    var title: Text { Text("Inside the nest") }
    var message: Text? {
        Text("Brood in the warm centre, pollen ringed around it, honey banked at the edges — the way a colony really arranges itself. Comb space, not forage, is what limits how much they can store.")
    }
    var image: Image? { Image(systemName: "hexagon.fill") }
}

struct ForageTip: Tip {
    var title: Text { Text("Distance is the cost") }
    var message: Text? {
        Text("Every flower sits at its real distance from the nest, and a forager burns honey to fly there and back. The same flowers three kilometres out return about a third of what they would at the entrance, and past eight kilometres the bees will not go at all.")
    }
    var image: Image? { Image(systemName: "map.fill") }
}

struct GardenTip: Tip {
    var title: Text { Text("Flowers go over") }
    var message: Text? {
        Text("A patch is at its best for about two months and gone a few months after that. The garden is a record of where you have been, so keep adding to it — and mind which families are missing this season.")
    }
    var image: Image? { Image(systemName: "photo.on.rectangle.angled") }
}

/// The only tip with a rule on it, and the rule exists to settle an ordering.
///
/// The gear is drawn over all four tabs, so without this it is eligible on the
/// very first screen — competing with the camera tip, which is the one that has
/// to land, and winning in whatever order TipKit happens to consider them.
/// Waiting until there is a flower in the garden puts it second by
/// construction, and is a better trigger anyway: "everything else is here" is
/// worth reading once the player has done the main thing, not before.
struct SettingsTip: Tip {

    @Parameter static var hasPhotographed: Bool = false

    var rules: [Rule] {
        #Rule(Self.$hasPhotographed) { $0 == true }
    }

    var title: Text { Text("Everything else is here") }
    var message: Text? {
        Text("Difficulty, moving the hive, the hour your morning report arrives, which notifications you want, and how to play.")
    }
    var image: Image? { Image(systemName: "gearshape.fill") }
}
