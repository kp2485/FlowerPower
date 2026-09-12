//
//  WatchRootView.swift
//  FlowerPower Watch
//
//  Pages, in order of how often you want them: the decision if there is one,
//  how the colony is, what the weather is doing to it, and the numbers.
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

    var body: some View {
        NavigationStack {
            if let summary = model.summary {
                TabView {
                    if let decision = summary.decision {
                        DecisionPage(decision: decision) { identifier in
                            model.answer(identifier)
                        }
                    }
                    StatusPage(summary: summary, isStale: model.isStale)
                    ConditionsPage(summary: summary)
                    NumbersPage(summary: summary)
                }
                .tabViewStyle(.verticalPage)
                .navigationTitle("Hive")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                WaitingView { model.refresh() }
            }
        }
        .onAppear { model.refresh() }
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
    var onAnswer: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: decision.kind.symbolName)
                        .foregroundStyle(WatchTheme.alarm)
                    Text(decision.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

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
                    Button(option.title) { onAnswer(option.identifier) }
                        .buttonStyle(.bordered)
                        .tint(WatchTheme.honey)
                        .frame(maxWidth: .infinity)
                }

                Text("Or leave it to the bees, which is what happens if you do nothing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
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

                if isStale {
                    Label("Out of touch with your phone", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

// MARK: - Numbers

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
                    .foregroundStyle(.tertiary)
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

    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hexagon")
                .font(.largeTitle)
                .foregroundStyle(WatchTheme.honey)
                .accessibilityHidden(true)
            Text("No colony yet")
                .font(.headline)
            Text("Open FlowerPower on your iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
