//
//  FlowerPowerWidgets.swift
//  FlowerPowerWidgets
//
//  The phone's Home Screen widget and its Live Activities.
//
//  The watch has had a complication since the start; the phone, where most
//  players are, had nothing on the Home Screen or the lock screen. The widget
//  here is the complication's provider and views ported across: the same
//  seasonal gauge, the same headline, the same save file.
//
//  The Live Activity is the more interesting half. A siege, a swarm gathering
//  and a mating flight all have durations, and this is what shows them on the
//  lock screen and in the Dynamic Island while they run.
//
//  A card can be up for two hours and more, and the first version of it was
//  one sentence for all of that time. Now it is a scene — who is at the
//  door, how many guards are on it, how roused the colony is — with the
//  answers on it as buttons, a clock and a ring that move by themselves, and
//  a last word on how it ended. What moves, moves without the app: the timer
//  text and the timer ring are the two things ActivityKit redraws on its own,
//  and everything else is what the app last wrote.
//

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import FlowerPowerCore
import FlowerPowerGame

@main
struct FlowerPowerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HiveWidget()
        HiveActivity()
        PhotographFlowerControl()
    }
}

// MARK: - The Home Screen widget

struct HiveWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WatchSummary?

    /// A decision the player can answer from the widget itself, if one is
    /// open. Carried on the entry rather than read in the view, because a
    /// timeline entry is the only thing a widget's body is allowed to see —
    /// and because the answer must be the one that will be true at the entry's
    /// date, not the one that was true when the timeline was built.
    var decision: OpenDecision?
}

struct HiveWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> HiveWidgetEntry {
        HiveWidgetEntry(date: Date(), summary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HiveWidgetEntry) -> Void) {
        completion(HiveWidgetEntry(date: Date(), summary: current()))
    }

    /// The engine is deterministic and time-driven, so future entries are
    /// computed exactly rather than guessed. The widget shows what *will* be
    /// true, not what was true an hour ago.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HiveWidgetEntry>) -> Void) {
        let now = Date()
        var entries: [HiveWidgetEntry] = []

        if var simulation = try? GamePersistence().load() {
            for hoursAhead in stride(from: 0, through: 6, by: 2) {
                let date = now.addingTimeInterval(TimeInterval(hoursAhead) * 3600)
                simulation.advance(to: date)
                entries.append(HiveWidgetEntry(
                    date: date,
                    summary: simulation.watchSummary(now: date),
                    decision: OpenDecision(simulation.snapshot())
                ))
            }
        } else {
            entries.append(HiveWidgetEntry(date: now, summary: nil))
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    private func current() -> WatchSummary? {
        guard var simulation = try? GamePersistence().load() else { return nil }
        simulation.advance(to: Date())
        return simulation.watchSummary()
    }
}

struct HiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.linwoodtechnologies.flowerpower.hive", provider: HiveWidgetProvider()) { entry in
            HiveWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("The Hive")
        .description("How the colony is doing, and what matters this season.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct HiveWidgetView: View {

    let entry: HiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let summary = entry.summary {
            switch family {
            case .accessoryInline:
                Label(summary.shortHeadline, systemImage: summary.status.symbolName)
            case .accessoryCircular:
                Gauge(value: summary.gauge.value) {
                    Image(systemName: summary.status.symbolName)
                }
                .gaugeStyle(.accessoryCircular)
                // The ring's only content is a status glyph, so there is
                // nothing here for a screen reader without saying it.
                .accessibilityLabel(summary.gauge.meaning.label)
                .accessibilityValue("\(summary.gauge.caption). \(summary.shortHeadline)")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label(summary.shortHeadline, systemImage: summary.status.symbolName)
                        .font(.headline)
                    Text(summary.gauge.caption).font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(summary.shortHeadline). \(summary.gauge.meaning.label): \(summary.gauge.caption)")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: summary.status.symbolName)
                            .foregroundStyle(WidgetTheme.colour(for: summary.status))
                            .accessibilityHidden(true)
                        Text(summary.status.displayName).font(.headline)
                        Spacer()
                        Image(systemName: WidgetTheme.symbol(for: summary.season))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(summary.season.displayName)
                    }
                    .accessibilityElement(children: .combine)
                    Text(summary.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                    Spacer(minLength: 0)
                    Gauge(value: summary.gauge.value) {
                        Text(summary.gauge.meaning.label)
                    } currentValueLabel: {
                        Text(summary.gauge.caption)
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(WidgetTheme.colour(for: summary.status))

                    // A decision displaces the counts rather than squeezing
                    // in beside them. A window that closes in a day is worth
                    // more than the population to two significant figures,
                    // and on a small widget there is only room for one of
                    // them.
                    if let decision = entry.decision {
                        BestAnswerButton(decision: decision)
                            .buttonStyle(.borderedProminent)
                            .tint(WidgetTheme.caution)
                            .font(.caption2)
                            .lineLimit(1)
                    } else {
                        HStack {
                            Label("\(summary.population)", systemImage: "hexagon.fill")
                                .accessibilityLabel("Bees")
                                .accessibilityValue("\(summary.population)")
                            Label("\(Int(summary.honey.rounded()))", systemImage: "drop.fill")
                                .accessibilityLabel("Honey")
                                .accessibilityValue("\(Int(summary.honey.rounded()))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            VStack {
                Image(systemName: "hexagon")
                    .accessibilityHidden(true)
                Text("No colony yet").font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Live Activities

struct HiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HiveActivityAttributes.self) { context in
            // The lock screen.
            HiveActivityCard(
                kind: context.attributes.kind,
                symbol: context.attributes.symbol,
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbol)
                        .font(.title2)
                        .foregroundStyle(activityTint(context.state))
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let target = countdownTarget(context.attributes.kind, context.state, isStale: context.isStale) {
                        // A timer's text takes all the width it is offered
                        // unless it is given a frame, and in the island that
                        // would push the headline out.
                        Text(timerInterval: span(context.state, to: target), countsDown: true)
                            .font(.headline.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activityStatus(context.attributes.kind, context.state, isStale: context.isStale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if showsAnswers(context.state, isStale: context.isStale) {
                            AnswerRow(answers: context.state.answers)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(activityTint(context.state))
                    .accessibilityLabel(context.state.title)
            } compactTrailing: {
                if let target = countdownTarget(context.attributes.kind, context.state, isStale: context.isStale) {
                    Text(timerInterval: span(context.state, to: target), countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                } else if context.state.phase == .resolved {
                    Image(systemName: context.state.repelled == false ? "xmark" : "checkmark")
                        .foregroundStyle(activityTint(context.state))
                        .accessibilityLabel(context.state.status)
                }
            } minimal: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(activityTint(context.state))
                    .accessibilityLabel(context.state.title)
            }
        }
    }
}

/// The lock-screen card: a headline, a line, the scene, a clock, and the
/// answers when there is a question. Kept under about 160 points, which is
/// where iOS starts cutting a Live Activity off.
struct HiveActivityCard: View {

    let kind: HiveActivityAttributes.Kind
    let symbol: String
    let state: HiveActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(activityTint(state))
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(activityStatus(kind, state, isStale: isStale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    // Stale numbers are worse than none: they are what was
                    // true when the app last ran, on a card that has already
                    // admitted it does not know what happened next.
                    if !isStale {
                        ActivityScene(state: state)
                            .padding(.top, 2)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 4)

                if let target = countdownTarget(kind, state, isStale: isStale) {
                    CountdownRing(
                        range: span(state, to: target),
                        caption: countdownCaption(kind, state),
                        tint: activityTint(state)
                    )
                }
            }

            if showsAnswers(state, isStale: isStale) {
                AnswerRow(answers: state.answers)
            }
        }
        .padding(14)
    }
}

/// The numbers that make the card a scene rather than a sentence. Each kind
/// of event fills in the ones it has, and only those are drawn.
struct ActivityScene: View {

    let state: HiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            if let guards = state.guards {
                Label("\(guards)", systemImage: "shield.fill")
                    .accessibilityLabel(guards == 1 ? "1 guard on the entrance" : "\(guards) guards on the entrance")
            }
            if let alarm = state.alarm {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    ProgressView(value: min(max(alarm, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(alarm > 0.5 ? WidgetTheme.alarm : WidgetTheme.caution)
                        .frame(width: 40)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Alarm")
                .accessibilityValue("\(Int((alarm * 100).rounded())) per cent")
            }
            if let lost = state.beesLost {
                Label("\(lost)", systemImage: "hexagon")
                    .accessibilityLabel(lost == 1 ? "1 bee lost" : "\(lost) bees lost")
            }
            if let stores = state.storesLost, stores >= 1 {
                Label("\(Int(stores.rounded()))", systemImage: "drop.fill")
                    .accessibilityLabel("\(Int(stores.rounded())) honey taken")
            }
            if let departing = state.departing {
                // An estimate while they gather, a count once they have gone.
                Label(state.phase == .resolved ? "\(departing)" : "~\(departing)", systemImage: "hexagon.fill")
                    .accessibilityLabel(state.phase == .resolved
                        ? "\(departing) bees left"
                        : "About \(departing) bees ready to leave")
            }
            if let cells = state.queenCells, cells > 0 {
                Label("\(cells)", systemImage: "crown.fill")
                    .accessibilityLabel(cells == 1 ? "1 queen cell" : "\(cells) queen cells")
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// A ring that fills and a clock that counts down, both redrawn by the
/// system with nothing from the app. They are the whole reason the card can
/// be up for two hours and still be worth looking at.
struct CountdownRing: View {

    let range: ClosedRange<Date>
    let caption: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(timerInterval: range, countsDown: true)
                .font(.caption.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: 66)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The answers, side by side. At most three — the swarm's — and short enough
/// in a caption to share a lock screen's width.
struct AnswerRow: View {

    let answers: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(answers, id: \.self) { identifier in
                if let action = DecisionAction(identifier: identifier) {
                    AnswerButton(action: action)
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(WidgetTheme.caution)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - What a card shows, decided once

// Free functions rather than methods, so the Dynamic Island's escaping
// builders have no `self` in them to argue about, and so the lock screen and
// the island cannot disagree about any of this.

/// What the card's clock counts to, or nil when it has no clock: a virgin
/// queen, because nobody can say when she will fly; an ended card; and a
/// stale one, whose clock would only count to a moment already past.
private func countdownTarget(
    _ kind: HiveActivityAttributes.Kind,
    _ state: HiveActivityAttributes.ContentState,
    isStale: Bool
) -> Date? {
    guard !isStale, kind != .matingFlight else { return nil }
    switch state.phase {
    case .deciding: return state.deadline
    case .holding: return state.resolvesAt
    case .resolved: return nil
    }
}

private func countdownCaption(
    _ kind: HiveActivityAttributes.Kind,
    _ state: HiveActivityAttributes.ContentState
) -> String {
    switch (state.phase, kind) {
    case (.deciding, _): return state.decisionOpen ? "Instinct in" : "Over in"
    case (.holding, .swarm): return "They choose in"
    case (.holding, _): return "Settled in"
    case (.resolved, _): return ""
    }
}

/// From the start of the event to the moment the clock counts to. A
/// `ClosedRange` whose ends are the wrong way round is a crash, not an empty
/// range, and the dates come from a save file, so this never trusts them.
private func span(_ state: HiveActivityAttributes.ContentState, to target: Date) -> ClosedRange<Date> {
    state.startedAt...max(state.startedAt, target)
}

private func showsAnswers(_ state: HiveActivityAttributes.ContentState, isStale: Bool) -> Bool {
    !isStale && state.phase == .deciding && state.decisionOpen && !state.answers.isEmpty
}

/// Past its stale date nothing has come back to take the card down — the app
/// is suspended and the background refresh has not been granted yet. It
/// should at least stop saying that something is happening, and say where
/// to find out what did.
private func activityStatus(
    _ kind: HiveActivityAttributes.Kind,
    _ state: HiveActivityAttributes.ContentState,
    isStale: Bool
) -> String {
    guard isStale else { return state.status }
    switch (state.phase, kind) {
    case (.resolved, _): return state.status
    case (_, .matingFlight): return "Open FlowerPower to see how she is getting on."
    case (.deciding, _): return "Left to instinct. Open FlowerPower to see how it goes."
    case (.holding, _): return "Settled by now. Open FlowerPower to see how it went."
    }
}

/// Amber while there is a question, honey while it runs, and at the end the
/// colour of how it went — green driven off, red not, honey for a swarm,
/// which is neither.
private func activityTint(_ state: HiveActivityAttributes.ContentState) -> Color {
    switch state.phase {
    case .deciding: return state.decisionOpen ? WidgetTheme.caution : WidgetTheme.honey
    case .holding: return WidgetTheme.honey
    case .resolved: return state.repelled.map { $0 ? WidgetTheme.healthy : WidgetTheme.alarm } ?? WidgetTheme.honey
    }
}

// MARK: - Control Centre

/// One tap from Control Centre, the lock screen or the Action button to the
/// only thing in the game that cannot be done from anywhere else.
///
/// The camera earns this place and nothing else does. Every other verb the app
/// has is either a decision, which arrives as a notification the moment it
/// matters, or reading, which wants the app open anyway. What a control is for
/// is the thing you want to do *while you are standing in front of it* — and
/// standing in front of a flower is how this game is played.
struct PhotographFlowerControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.linwoodtechnologies.flowerpower.photograph") {
            ControlWidgetButton(action: PhotographFlowerIntent()) {
                Label("Photograph a Flower", systemImage: "camera.macro")
            }
        }
        .displayName("Photograph a Flower")
        .description("Opens FlowerPower on the camera, to add a flower to your garden.")
    }
}

// MARK: - Theme, trimmed for the extension

enum WidgetTheme {
    static let honey = Color(red: 0.93, green: 0.68, blue: 0.13)
    static let alarm = Color(red: 0.82, green: 0.25, blue: 0.20)
    static let caution = Color(red: 0.90, green: 0.55, blue: 0.10)
    static let healthy = Color(red: 0.30, green: 0.62, blue: 0.36)

    static func colour(for status: ColonyStatus) -> Color {
        switch status {
        case .collapsed: return .secondary
        case .critical: return alarm
        case .struggling: return caution
        case .steady: return honey
        case .thriving: return healthy
        }
    }

    /// The engine owns the symbol names — see `Symbols.swift` in the package.
    /// This was the same switch a third time.
    static func symbol(for season: Season) -> String { season.symbolName }
}
