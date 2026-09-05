//
//  WatchRootView.swift
//  FlowerPower Watch
//
//  Three pages, in order of how often you want them: how the colony is, what
//  the weather is doing to it, and the numbers.
//

import SwiftUI
import FlowerPowerCore

struct WatchRootView: View {

    @Environment(WatchColonyModel.self) private var model

    var body: some View {
        NavigationStack {
            if let summary = model.summary {
                TabView {
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
                        value: summary.season.displayName,
                        tint: WatchTheme.honey
                    )
                    WatchReading(
                        symbol: "thermometer.medium",
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
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WatchReading: View {

    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
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
