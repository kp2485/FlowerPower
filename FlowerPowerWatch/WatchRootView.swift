//
//  WatchRootView.swift
//  FlowerPower Watch
//
//  Pages, in order of how often you want them: the decision if there is one,
//  how the colony is, what the weather is doing to it, and the readings — the
//  phone's overview at its symbol tier, a glyph and a number apiece.
//
//  The decision page is first rather than last for the same reason the watch
//  exists at all. The design rule is that every decision the game asks is
//  answerable from a wrist, and a page reached by scrolling past three others
//  is not answerable so much as findable. When there is nothing to decide the
//  page is not there, so the colony's state is what a glance lands on.
//

import SwiftUI
import FlowerPowerCore

struct WatchRootView: View {

    @Environment(WatchColonyModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if let summary = model.summary {
                TabView {
                    if let decision = summary.decision {
                        DecisionPage(decision: decision) { identifier in
                            model.answer(identifier)
                        }
                        // A different decision is a different page, with its
                        // own count of answers.
                        .id(decision.kind)
                    }
                    StatusPage(summary: summary, isStale: model.isStale, isOutOfStep: model.isOutOfStep)
                    ConditionsPage(summary: summary)
                    if summary.readings.isEmpty {
                        // A phone built before the readings were sent.
                        NumbersPage(summary: summary)
                    } else {
                        ReadingsPage(summary: summary)
                    }
                }
                .tabViewStyle(.verticalPage)
                .navigationTitle("Hive")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                WaitingView(isOutOfStep: model.isOutOfStep) { model.refresh() }
            }
        }
        .onAppear { model.refresh() }
        // A raised wrist brings a suspended app back without an appearance, so
        // this is what stops hours-old numbers being shown as current.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }
}

// MARK: - A decision

/// The question, what it costs, and a button for each answer.
///
/// Instinct is not among the buttons, on purpose. Doing nothing is what happens
/// if the player never looks, so a button for it would spend one of the three
/// places a watch screen has on the outcome the player already has. The page
/// says so in a line instead.
private struct DecisionPage: View {

    let decision: WatchDecision
    /// Takes a `DecisionAction` identifier, which the model parses. The view
    /// deliberately knows nothing about what the answers mean.
    /// Returns whether the answer took.
    var onAnswer: (String) -> Bool

    /// Answering from the wrist deserves the same tap the phone gives. The
    /// model plays a haptic when a decision *arrives*; nothing marked the
    /// answer going back.
    @State private var answers = 0
    @State private var refused = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: decision.kind.symbolName)
                        .foregroundStyle(WatchTheme.alarm)
                        .accessibilityHidden(true)
                    Text(decision.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)

                if let days = decision.daysRemaining {
                    Text(remaining(days))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(decision.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(decision.options, id: \.identifier) { option in
                    Button(option.title) {
                        if onAnswer(option.identifier) {
                            answers += 1
                        } else {
                            refused += 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(WatchTheme.honey)
                    .frame(maxWidth: .infinity)
                }

                Text("Or leave it to the bees, which is what happens if you do nothing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .sensoryFeedback(.success, trigger: answers)
        .sensoryFeedback(.warning, trigger: refused)
    }

    private func remaining(_ days: Int) -> String {
        switch days {
        case ..<1: return "Decided today"
        case 1: return "1 day to decide"
        default: return "\(days) days to decide"
        }
    }
}

// MARK: - Status

private struct StatusPage: View {

    let summary: WatchSummary
    let isStale: Bool
    let isOutOfStep: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Gauge(value: summary.gauge.value) {
                    Text(summary.gauge.meaning.label)
                } currentValueLabel: {
                    Image(systemName: summary.status.symbolName)
                        .foregroundStyle(WatchTheme.colour(for: summary.status))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [WatchTheme.alarm, WatchTheme.caution, WatchTheme.healthy]))
                .scaleEffect(1.25)
                .padding(.vertical, 8)
                // What the gauge measures changes with the season, and the
                // only thing in the ring itself is a status glyph.
                .accessibilityLabel(summary.gauge.meaning.label)
                .accessibilityValue(summary.gauge.caption)

                Text(summary.shortHeadline)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WatchTheme.colour(for: summary.status))

                Text(summary.gauge.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let alert = summary.topAlert, alert.severity >= .warning {
                    VStack(spacing: 3) {
                        Text(alert.title)
                            .font(.caption.weight(.semibold))
                        Text(alert.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(
                        WatchTheme.colour(for: alert.severity).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .accessibilityElement(children: .combine)
                }

                if isOutOfStep {
                    // Not "out of touch": the phone is talking, and this app
                    // cannot read what it says. Only updating fixes that.
                    Label("Update FlowerPower on your phone and watch to keep them in step",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if isStale {
                    Label("Out of touch with your phone", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Conditions

private struct ConditionsPage: View {

    let summary: WatchSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label(summary.headline, systemImage: summary.isForaging ? "figure.walk.motion" : "house.fill")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    WatchReading(
                        symbol: WatchTheme.symbol(for: summary.season),
                        label: "Season",
                        value: summary.season.displayName,
                        tint: WatchTheme.honey
                    )
                    WatchReading(
                        symbol: "thermometer.medium",
                        label: "Brood nest",
                        value: String(format: "%.0f°", summary.temperatureCelsius),
                        tint: abs(summary.temperatureCelsius - 35) < 2
                            ? WatchTheme.healthy
                            : WatchTheme.caution
                    )
                }

                Text(summary.isForaging
                     ? "The bees are out working."
                     : "The bees are in the nest.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Readings

/// The phone's overview at its symbol tier: every reading as a glyph in the
/// colour of how worried to be and the one number, two abreast. A wrist has
/// no room for the words, so the words are what a tap opens, and what
/// VoiceOver reads.
private struct ReadingsPage: View {

    let summary: WatchSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(summary.readings) { reading in
                        NavigationLink {
                            ReadingDetail(reading: reading)
                        } label: {
                            ReadingCell(reading: reading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(summary.generatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct ReadingCell: View {

    let reading: WatchSummary.Reading

    private var tint: Color { WatchTheme.colour(for: reading.severity) }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: reading.symbolName)
                .font(.footnote)
                .foregroundStyle(tint)
            Text(reading.headline)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.title)
        .accessibilityValue(reading.spoken)
        .accessibilityHint("Shows the reading in words")
    }
}

/// The words behind a glyph.
private struct ReadingDetail: View {

    let reading: WatchSummary.Reading

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: reading.symbolName)
                    .font(.title3)
                    .foregroundStyle(WatchTheme.colour(for: reading.severity))
                Text(reading.headline)
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(reading.spoken)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(reading.title)
    }
}

// MARK: - Numbers

/// What the watch showed before the phone sent readings, kept for a phone
/// that still does not.
private struct NumbersPage: View {

    let summary: WatchSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchStatRow(label: "Bees", value: "\(summary.population)", tint: WatchTheme.worker)
                WatchStatRow(label: "Brood", value: "\(summary.broodCount)", tint: WatchTheme.honey)
                WatchStatRow(label: "Honey", value: String(format: "%.0f", summary.honey), tint: WatchTheme.honey)
                WatchStatRow(label: "Day", value: "\(summary.day)", tint: .secondary)

                Text(summary.generatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct WatchStatRow: View {

    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WatchReading: View {

    let symbol: String
    /// Spoken only. On screen the symbol is the label, which works for a
    /// thermometer and not at all for a screen reader.
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Waiting

private struct WaitingView: View {

    var isOutOfStep = false
    var onRetry: () -> Void

    /// In a scroll view because it does not fit otherwise. Held to the
    /// screen's height, the caption was cut to "Open FlowerPower on you…" on
    /// the first run — on an Ultra, the largest watch there is.
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "hexagon")
                    .font(.largeTitle)
                    .foregroundStyle(WatchTheme.honey)
                    .accessibilityHidden(true)
                Text(isOutOfStep ? "Out of step" : "No colony yet")
                    .font(.headline)
                Text(isOutOfStep
                     ? "Update FlowerPower on your iPhone and watch."
                     : "Open FlowerPower on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
