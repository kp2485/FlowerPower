//
//  AppIntents.swift
//  FlowerPower
//
//  The colony, reachable without the app.
//
//  Four places want the same handful of verbs, and App Intents is the one
//  mechanism that serves them all: Siri and Shortcuts ("how are my bees?"),
//  the buttons on the Home Screen widget, the buttons on a Live Activity, and
//  the Control Centre control that opens the camera. Writing them once here
//  is the whole point — a Shortcut and a card button that answer a siege
//  differently would be two chances to get the same decision wrong.
//
//  The decisions a card can take are `LiveActivityIntent`s. That is what
//  makes a button on a Live Activity run *in the app's process* rather than
//  the widget extension's — and only the app can update an activity. So the
//  card that asked the question changes the moment it is answered, through
//  `ColonyIntents.onDecided`, instead of whenever the app is next opened.
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
//  The running app is handled on the other side. `GameStore` holds the
//  simulation in memory and saves over the file on every catch-up, which
//  would lose a decision written here while the interface was in the
//  foreground — so the store asks its persistence for a change token before
//  it advances, and reloads the file if somebody else wrote it. See
//  `GameStore.takeInOutsideChanges()`. Nothing here needs to know.
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

/// Every answer to a siege or a swarm is a `LiveActivityIntent`, because
/// every one of them can be a button on a card: see the top of the file. It changes nothing for Siri or a Shortcut, and on the Home Screen
/// widget it means the card beside it changes too.
///
/// `perform` is on the main actor because `ColonyIntents` is — it holds the
/// app's hook — and at no cost, for the reason `CheckColonyIntent` gives.
struct HoldEntranceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Hold the Entrance" }
    /// Each of these repeats `HivePosture.detail` word for word rather than
    /// reading it. The App Intents metadata step extracts titles and
    /// descriptions at build time without running any code, and it fails the
    /// build on an interpolated one — which is what the first Mac build found.
    /// Change the engine's sentence and this one together.
    static var description: IntentDescription {
        IntentDescription("Every bee that can sting meets the attacker at the door. Fewer foragers out, and defenders die doing it.")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .holdEntrance)
        return .result()
    }
}

struct NarrowEntranceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Narrow the Entrance" }
    static var description: IntentDescription {
        IntentDescription("Propolis narrows the entrance to a slot. Hard to force, hard to rob, slow to fly through.")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
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
struct KeepForagersHomeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Keep the Foragers Home" }
    static var description: IntentDescription {
        IntentDescription("Nobody goes out. Nothing for an ambusher to take, and nothing coming in.")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .foragersHome)
        return .result()
    }
}

struct SendInCleanersIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Send in the Cleaners" }
    static var description: IntentDescription {
        IntentDescription("Cleaners hunt the comb for moth and beetle larvae, at the expense of everything else.")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.answerSiege(with: .cleanersOut)
        return .result()
    }
}

// MARK: - Answering a swarm

struct MakeRoomIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Make Room" }

    static var description: IntentDescription {
        // The best answer to a swarm there is: 76% two-year survival against
        // 66% for doing nothing, 62% for opening the nest up and 56% for
        // dividing. See `NotificationActions.register`.
        IntentDescription("Builders draw comb and foragers hold back, to ease the crowding that sends a swarm out.")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.makeRoom()
        return .result()
    }
}

/// The other two answers a swarm card offers, in the order the notification
/// offers them. Each is on the card only when the engine would honour it —
/// `LiveActivityPlan` checks — and each checks again here, because a card
/// can be answered an hour after it was drawn.
struct OpenNestUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Open the Nest Up" }

    static var description: IntentDescription {
        IntentDescription("Draws new comb now, paid for in the honey it takes to make the wax.")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.openNestUp()
        return .result()
    }
}

struct DivideColonyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Divide the Colony" }

    static var description: IntentDescription {
        IntentDescription("Moves the queen and the house bees out now, before the colony divides itself. Fewer go than would leave in a swarm.")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.divide()
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

    @MainActor
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

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.decideEntrance(sealed: false)
        return .result()
    }
}

// MARK: - Looking at the country

struct SendScoutsIntent: AppIntent {
    static var title: LocalizedStringResource { "Send Scouts" }

    /// A literal, like every other description here: the App Intents metadata
    /// step extracts these at build time without running anything, and an
    /// interpolated string is not something it can read.
    static var description: IntentDescription {
        IntentDescription("Sends a tenth of the foragers to look at the ground nobody has been to. They are gone for three days and come back with all of it.")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        ColonyIntents.sendScouts()
        return .result()
    }
}

// MARK: - Acting on the save

@MainActor
enum ColonyIntents {

    private static let logger = Logger(
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "intents"
    )

    /// What the app does after a decision is saved: bring the Live
    /// Activities into line with it, so the card whose button was just tapped
    /// stops asking. See `FlowerPowerApp.init`.
    ///
    /// A hook rather than a call, because this file is compiled into the
    /// widget extension too and `LiveActivities` is not — nor could it be,
    /// since only the app can update an activity. In the extension this is
    /// nil and nothing happens, which is correct: a decision performed there
    /// came from a button that is not a `LiveActivityIntent`, and the app
    /// reconciles on its next catch-up as it always did.
    static var onDecided: (@MainActor @Sendable (Simulation) -> Void)?

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
        // And so is the card, if it was pressed on a card.
        onDecided?(simulation)
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

    /// Draws comb now. The same checks `GameStore.apply(.addComb)` makes: it
    /// does not ask whether a swarm is still pending, because room is worth
    /// having either way, only whether any comb was actually drawn.
    @discardableResult
    static func openNestUp() -> Bool {
        decide { simulation in
            simulation.addComb() > 0
        }
    }

    /// Divides the colony, checked hard, as `GameStore.apply(.split)` is: a
    /// division after the colony has already swarmed would send away a second
    /// half of a colony that has just lost the first.
    @discardableResult
    static func divide() -> Bool {
        decide { simulation in
            guard simulation.world.pendingSwarm != nil, simulation.canSplit else { return false }
            return simulation.split()
        }
    }

    /// The one decision the world adds.
    ///
    /// Stale in the ordinary way — a Shortcut can run long after the flow that
    /// paid for the party has ended, and the foragers may have found the last
    /// of the rumoured ground themselves. `Simulation.sendScouts` checks it
    /// again and returns false rather than sending anybody; the guard here
    /// says so where it can be read.
    @discardableResult
    static func sendScouts() -> Bool {
        decide { simulation in
            guard simulation.scoutDecisionOpen else { return false }
            return simulation.sendScouts()
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
/// window goes first. Scouting goes last, matching the engine's own priority:
/// it is the only one of the three that is offered while things are going
/// well, and it can wait for the length of the flow.
enum OpenDecision: Equatable, Sendable {

    case siege(HivePosture)
    case swarm
    case scout

    init?(_ snapshot: ColonySnapshot) {
        if let posture = snapshot.activeThreat?.options.first(where: { $0 != .instinct }) {
            self = .siege(posture)
        } else if let swarm = snapshot.pendingSwarm, !swarm.discouraged {
            self = .swarm
        } else if snapshot.scoutDecisionOpen {
            self = .scout
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
        button
            // On a widget the button is the only thing there is, so its own
            // words — "Make Room", "Hold the Entrance" — are an answer with
            // the question missing. The label carries the question.
            .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder
    private var button: some View {
        switch decision {
        case .swarm:
            Button(intent: MakeRoomIntent()) {
                Label(
                    HivePosture.makeRoom.displayName,
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                )
            }
        case .scout:
            Button(intent: SendScoutsIntent()) {
                Label(DecisionAction.scout.title, systemImage: "binoculars.fill")
            }
        case .siege(let posture):
            siegeButton(posture)
        }
    }

    private var spokenLabel: String {
        switch decision {
        case .swarm:
            return "\(HivePosture.makeRoom.displayName). Answers the swarm the colony is preparing."
        case .scout:
            return "\(DecisionAction.scout.title). Sends a party to the ground nobody has been to."
        case .siege(let posture):
            return "\(posture.displayName). Answers what is at the entrance."
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

// MARK: - Any answer a card offers

/// One answer as a button, for a Live Activity that offers several.
///
/// `BestAnswerButton` is the widget's: one decision, its best answer. A card
/// shows every answer the plan chose, so it needs the whole map from
/// `DecisionAction` to an intent — and like that one, it is written once and
/// here, where the compiler can see the switch is exhaustive.
///
/// Words only, no symbol: a card has room for three buttons side by side and
/// not for three icons as well.
struct AnswerButton: View {

    let action: DecisionAction

    var body: some View {
        button
            // The card's headline says what is being answered, but a screen
            // reader reaching the buttons has left the headline behind.
            .accessibilityHint(hint)
    }

    @ViewBuilder
    private var button: some View {
        switch action {
        case .posture(.holdEntrance):
            Button(intent: HoldEntranceIntent()) { label }
        case .posture(.narrowEntrance):
            Button(intent: NarrowEntranceIntent()) { label }
        case .posture(.foragersHome):
            Button(intent: KeepForagersHomeIntent()) { label }
        case .posture(.cleanersOut):
            Button(intent: SendInCleanersIntent()) { label }
        case .discourageSwarm:
            Button(intent: MakeRoomIntent()) { label }
        case .addComb:
            Button(intent: OpenNestUpIntent()) { label }
        case .split:
            Button(intent: DivideColonyIntent()) { label }
        case .posture(.instinct), .posture(.makeRoom),
             .letSwarmGo, .staySwarm, .sealEntrance, .openEntrance, .feed, .scout:
            // Nothing the plan puts on a card. A card that somehow carried one
            // draws nothing for it rather than a button that does nothing.
            EmptyView()
        }
    }

    private var label: some View {
        Text(action.title)
            .frame(maxWidth: .infinity)
    }

    private var hint: String {
        switch action {
        case .discourageSwarm, .addComb, .split:
            return "Answers the swarm the colony is preparing."
        default:
            return "Answers what is at the nest."
        }
    }
}
