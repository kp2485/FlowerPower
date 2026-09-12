//
//  AppIntents.swift
//  FlowerPower
//
//  The colony, reachable without the app.
//
//  Three places want the same handful of verbs, and App Intents is the one
//  mechanism that serves all three: Siri and Shortcuts ("how are my bees?"),
//  the buttons on the Home Screen widget, and the Control Centre control that
//  opens the camera. Writing them once here is the whole point — a Shortcut
//  and a widget button that answer a siege differently would be two chances
//  to get the same decision wrong.
//
//  Two rules shape everything below.
//
//  **A question never writes.** `CheckColonyIntent` loads the save, advances a
//  copy in memory and reads it. It does not save. Asking how the bees are is
//  not a move in the game and must not be able to lose one.
//
//  **A decision acts on the save file, and checks it is still open first.**
//  This is the same problem `NotificationActions.handle` solves, and it is
//  solved the same way, deliberately: an intent can be run from Control
//  Centre, from a widget, or by Siri with the app not loaded at all, so the
//  file is the only thing there is to act on. What it is *not* is shared code
//  with that function, because `NotificationActions` is compiled into the app
//  alone and this file is compiled into the widget extension as well — where
//  the only thing in scope is the package. See `project.yml`.
//
//  What that leaves uncertain is the running app. `GameStore` holds the
//  simulation in memory and saves over the file on every catch-up, so a
//  decision written here while the interface is in the foreground is lost at
//  the store's next tick. That is exactly the behaviour a tapped notification
//  action has today, and fixing it belongs in `GameStore` — reload when the
//  file on disk is newer than the last save it wrote — rather than in each
//  intent separately. In practice the foreground case barely arises: a widget
//  button and a Control Centre control are both pressed from outside the app.
//

import Foundation
import AppIntents
import SwiftUI
import WidgetKit
import FlowerPowerCore
import FlowerPowerGame
import os

// MARK: - Asking how the bees are

struct CheckColonyIntent: AppIntent {

    static var title: LocalizedStringResource { "How Are My Bees" }

    static var description: IntentDescription {
        IntentDescription("Asks the colony how it is doing, in a sentence or two.")
    }

    /// Answered where it was asked. Opening the app to read out a sentence
    /// would defeat the point of asking.
    static var openAppWhenRun: Bool { false }

    /// On the main actor for the snippet's sake — it is a SwiftUI view — and
    /// at no cost: this is the same load and catch-up the app itself does on
    /// the main actor at every launch.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard var simulation = try? GamePersistence().load() else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: "There is no colony yet. Photograph a flower "
                        + "and a swarm will find you."
                ),
                view: HiveSnippet(summary: nil)
            )
        }

        // Advanced but not saved. The engine is handed a date and works out
        // what should have happened, so this is the true state of the colony
        // whether or not anything writes it down.
        simulation.advance(to: Date())

        return .result(
            dialog: IntentDialog(stringLiteral: simulation.snapshot().spokenStatus),
            view: HiveSnippet(summary: simulation.watchSummary())
        )
    }
}

/// What Siri shows while it reads the sentence out.
///
/// The gauge rather than the numbers, because the gauge is the one thing the
/// spoken answer cannot carry: `WatchSummary` picks the measure that matters
/// this season, and a bar is worth more at a glance than "eighty-two per cent
/// of the winter requirement" is in the ear.
struct HiveSnippet: View {

    let summary: WatchSummary?

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 8) {
                Label(summary.shortHeadline, systemImage: summary.status.symbolName)
                    .font(.headline)
                Gauge(value: summary.gauge.value) {
                    Text(summary.gauge.meaning.label)
                } currentValueLabel: {
                    Text(summary.gauge.caption)
                }
                .gaugeStyle(.accessoryLinear)
            }
            .padding()
        } else {
            Label("No colony yet", systemImage: "hexagon")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

// MARK: - Going out to photograph

struct PhotographFlowerIntent: AppIntent {

    static var title: LocalizedStringResource { "Photograph a Flower" }

    static var description: IntentDescription {
        IntentDescription("Opens FlowerPower on the camera, to add a flower to your garden.")
    }

    /// The only intent here that needs the interface, and it needs all of it:
    /// a camera, the photo library and the identification that follows.
    static var openAppWhenRun: Bool { true }

    /// What the interface is asked for, by identifier.
    ///
    /// The same channel a notification action uses when it cannot be completed
    /// from the lock screen — see `NotificationDelegate.onOpenApp` and
    /// `ContentView`'s `requestedAction` — rather than a second way for the
    /// same request to arrive.
    static let actionPrefix = "intent.photographFlower"

    @MainActor
    func perform() async throws -> some IntentResult {
        // A nonce, because the interface reacts to the requested action
        // *changing*. A player who asks twice must be taken to the camera
        // twice, and the second request would otherwise be the same string as
        // the first and land as no change at all.
        AppIntentRequests.request("\(Self.actionPrefix).\(UUID().uuidString)")
        return .result()
    }
}

/// Where an intent that needs the interface hands its request over.
///
/// Assigning `onOpenApp` delivers anything that arrived before it, which on a
/// cold launch is the normal case rather than the exception: an intent with
/// `openAppWhenRun` performs while the window is still being built, so the
/// request routinely beats the view that handles it.
@MainActor
enum AppIntentRequests {

    private static var pending: String?

    static var onOpenApp: (@MainActor @Sendable (String) -> Void)? {
        didSet {
            guard let action = pending, let deliver = onOpenApp else { return }
            pending = nil
            deliver(action)
        }
    }

    static func request(_ action: String) {
        if let onOpenApp {
            onOpenApp(action)
        } else {
            pending = action
        }
    }
}

// MARK: - Answering a siege

struct HoldEntranceIntent: AppIntent {
    static var title: LocalizedStringResource { "Hold the Entrance" }
    static var description: IntentDescription {
        IntentDescription("\(HivePosture.holdEntrance.detail)")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .holdEntrance)
        return .result()
    }
}

struct NarrowEntranceIntent: AppIntent {
    static var title: LocalizedStringResource { "Narrow the Entrance" }
    static var description: IntentDescription {
        IntentDescription("\(HivePosture.narrowEntrance.detail)")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .narrowEntrance)
        return .result()
    }
}

/// The other two answers, and why they are here rather than left out.
///
/// A siege comes in four styles and `HivePosture.options(against:)` answers
/// all four: guards or a narrowed entrance at the door, the foragers kept in
/// against a bird working the flowers, the cleaners turned out against larvae
/// in the comb. The widget shows the first option against whatever has
/// arrived, so an intent missing for two of the four styles would not be a
/// smaller feature — it would be a widget that shows a siege and offers
/// nothing to do about it half the time.
struct KeepForagersHomeIntent: AppIntent {
    static var title: LocalizedStringResource { "Keep the Foragers Home" }
    static var description: IntentDescription {
        IntentDescription("\(HivePosture.foragersHome.detail)")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .foragersHome)
        return .result()
    }
}

struct SendInCleanersIntent: AppIntent {
    static var title: LocalizedStringResource { "Send in the Cleaners" }
    static var description: IntentDescription {
        IntentDescription("\(HivePosture.cleanersOut.detail)")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .cleanersOut)
        return .result()
    }
}

// MARK: - Answering a swarm

struct MakeRoomIntent: AppIntent {
    static var title: LocalizedStringResource { "Make Room" }

    static var description: IntentDescription {
        // The best answer to a swarm there is: 76% two-year survival against
        // 66% for doing nothing, 62% for opening the nest up and 56% for
        // dividing. See `NotificationActions.register`.
        IntentDescription("\(HivePosture.makeRoom.detail)")
    }

    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.makeRoom()
        return .result()
    }
}

// MARK: - The autumn entrance

struct SealEntranceIntent: AppIntent {
    static var title: LocalizedStringResource { "Seal the Entrance" }
    static var description: IntentDescription {
        IntentDescription("Lets the bees propolise the entrance down for winter.")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.decideEntrance(sealed: true)
        return .result()
    }
}

struct KeepEntranceOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "Keep the Entrance Open" }
    static var description: IntentDescription {
        IntentDescription("Keeps the entrance open through the winter.")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        ColonyIntents.decideEntrance(sealed: false)
        return .result()
    }
}

// MARK: - Acting on the save

enum ColonyIntents {

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
        category: "intents"
    )

    /// Applies a decision to the saved colony, with no interface running.
    ///
    /// `change` returns whether it actually did anything. Nothing is written
    /// when it did not, which is what keeps a stale run harmless: a Shortcut
    /// can sit in somebody's automation for a fortnight, and by the time it
    /// runs the siege it was written for is long over.
    @discardableResult
    static func decide(
        persistence: GamePersisting = GamePersistence(),
        now: Date = Date(),
        _ change: (inout Simulation) -> Bool
    ) -> Bool {
        guard var simulation = try? persistence.load() else { return false }
        simulation.advance(to: now)
        guard change(&simulation) else { return false }

        do {
            try persistence.save(simulation)
        } catch {
            logger.error("could not save an intent's decision: \(error.localizedDescription)")
            return false
        }

        // The widget is very likely showing the button that was just pressed.
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// Answers whatever is at the nest with a posture.
    ///
    /// Stale in two directions, and both do nothing rather than something
    /// wrong. The siege may be over — a Shortcut does not know what year it
    /// is. And the posture may be no answer to *this* attack: guards at the
    /// door against a shrike taking foragers in the field would cost a third
    /// of the forage and change nothing at all.
    @discardableResult
    static func answerSiege(with posture: HivePosture) -> Bool {
        decide { simulation in
            guard let threat = simulation.world.activeThreat,
                  threat.options.contains(posture)
            else { return false }
            simulation.respond(to: threat, with: posture)
            return true
        }
    }

    @discardableResult
    static func makeRoom() -> Bool {
        decide { simulation in
            guard simulation.world.pendingSwarm != nil else { return false }
            simulation.discourageSwarm()
            return true
        }
    }

    /// The autumn decision.
    ///
    /// Gated on the season because that is the only time the engine honours it
    /// — see `Simulation.decideEntrance` — and a Shortcut run in June would
    /// otherwise write a save that says nothing happened.
    @discardableResult
    static func decideEntrance(sealed: Bool) -> Bool {
        decide { simulation in
            guard simulation.season == .autumn else { return false }
            simulation.decideEntrance(sealed: sealed)
            return true
        }
    }
}

// MARK: - The decision a widget can answer

/// A decision open right now, with the best answer to it already chosen.
///
/// The choosing is the package's, not this file's: `HivePosture.options`
/// returns the postures worth offering against an attack in measured order,
/// so its first entry is the best answer there is, and making room is the
/// best answer to a swarm. A widget has room for one button and it should be
/// that one.
///
/// Ordered siege before swarm, matching `ColonyNews`: a siege resolves in a
/// day or two and a swarm takes the better part of a week, so the tighter
/// window goes first.
enum OpenDecision: Equatable, Sendable {

    case siege(HivePosture)
    case swarm

    init?(_ snapshot: ColonySnapshot) {
        if let posture = snapshot.activeThreat?.options.first(where: { $0 != .instinct }) {
            self = .siege(posture)
        } else if let swarm = snapshot.pendingSwarm, !swarm.discouraged {
            self = .swarm
        } else {
            return nil
        }
    }
}

/// The best answer as a button that acts without opening the app.
///
/// The switch over `HivePosture` is the one thing in this feature that could
/// not be put in the package: it maps an engine type onto App Intents types,
/// and the package must build on Windows, where `AppIntents` does not exist.
/// It is written once, here, rather than in the widget and the app separately,
/// so there is a single place for the compiler to find it non-exhaustive.
struct BestAnswerButton: View {

    let decision: OpenDecision

    var body: some View {
        switch decision {
        case .swarm:
            Button(intent: MakeRoomIntent()) {
                Label(
                    HivePosture.makeRoom.displayName,
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                )
            }
        case .siege(let posture):
            siegeButton(posture)
        }
    }

    @ViewBuilder
    private func siegeButton(_ posture: HivePosture) -> some View {
        switch posture {
        case .holdEntrance:
            Button(intent: HoldEntranceIntent()) { label(posture) }
        case .narrowEntrance:
            Button(intent: NarrowEntranceIntent()) { label(posture) }
        case .foragersHome:
            Button(intent: KeepForagersHomeIntent()) { label(posture) }
        case .cleanersOut:
            Button(intent: SendInCleanersIntent()) { label(posture) }
        case .instinct, .makeRoom:
            // Neither is an answer to a siege, and `HivePosture.options`
            // never offers them as one. Nothing to draw rather than a button
            // that would do nothing.
            EmptyView()
        }
    }

    /// One symbol for every posture, on purpose: the button is an act of
    /// defence whichever posture it carries, and the words say which.
    private func label(_ posture: HivePosture) -> some View {
        Label(posture.displayName, systemImage: "shield.fill")
    }
}
