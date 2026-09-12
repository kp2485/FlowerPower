//
//  HiveComplication.swift
//  FlowerPower Watch
//
//  The complication is the real watch feature. Everything else on the watch is
//  a nicety; a gauge on the face that quietly goes amber when the colony is
//  short of winter stores is a thing you would actually want.
//
//  What the gauge measures changes with the season, because a fixed metric
//  would waste the one slot available for most of the year. In autumn it is
//  winter stores; in a crisis it is health; in a summer flow it is nest space.
//  `Simulation.watchSummary()` decides, so the phone and the watch never
//  disagree about what matters today.
//
//  A decision outranks all of it. The gauge is a report and a decision is the
//  colony asking for something, with a window on it — so while one is open the
//  complication shows the question rather than the measurement. That is the
//  whole of what a glance is for: not "stores are at 60%" but "they are about
//  to swarm and you have two days".
//

import WidgetKit
import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

// MARK: - Entry

struct HiveEntry: TimelineEntry {
    let date: Date
    let summary: WatchSummary?

    /// Shown in the widget gallery and when there is no colony yet.
    static func placeholder(at date: Date = Date()) -> HiveEntry {
        HiveEntry(date: date, summary: nil)
    }
}

// MARK: - Provider

struct HiveProvider: TimelineProvider {

    func placeholder(in context: Context) -> HiveEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (HiveEntry) -> Void) {
        completion(HiveEntry(date: Date(), summary: currentSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HiveEntry>) -> Void) {
        let now = Date()

        // The engine is deterministic and time-driven, so future entries can be
        // computed exactly rather than guessed. That means the complication
        // stays correct between refreshes instead of going stale — it is
        // showing what *will* be true, not what was true an hour ago.
        var entries: [HiveEntry] = []

        // The watch's own copy of the save, which the phone sends across by
        // file transfer. An App Group is shared between processes on one
        // device, never between devices, so this is the phone's colony only
        // because `WatchColonyModel` wrote it here when it arrived.
        if var simulation = try? GamePersistence().load() {
            for hoursAhead in stride(from: 0, through: 8, by: 2) {
                let date = now.addingTimeInterval(TimeInterval(hoursAhead) * 3600)
                simulation.advance(to: date)
                entries.append(HiveEntry(date: date, summary: simulation.watchSummary(now: date)))
            }
        } else {
            entries.append(HiveEntry(date: now, summary: nil))
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(8 * 3600))))
    }

    private func currentSummary() -> WatchSummary? {
        guard var simulation = try? GamePersistence().load() else { return nil }
        simulation.advance(to: Date())
        return simulation.watchSummary()
    }
}

// MARK: - Views

struct HiveComplicationView: View {

    @Environment(\.widgetFamily) private var family
    let entry: HiveEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(summary: entry.summary)
        case .accessoryCorner:
            CornerView(summary: entry.summary)
        case .accessoryInline:
            InlineView(summary: entry.summary)
        case .accessoryRectangular:
            RectangularView(summary: entry.summary)
        default:
            CircularView(summary: entry.summary)
        }
    }
}

private struct CircularView: View {

    let summary: WatchSummary?

    var body: some View {
        Gauge(value: summary?.gauge.value ?? 0) {
            Image(systemName: "hexagon.fill")
        } currentValueLabel: {
            // The badge, on the one slot this family has. A shield, a swarm or
            // a door in the middle of the gauge says the colony is waiting on
            // an answer; the status icon says it is not.
            if let decision = summary?.decision {
                Image(systemName: decision.kind.symbolName)
            } else if let summary {
                Image(systemName: summary.status.symbolName)
            } else {
                Image(systemName: "hexagon")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeTint)
        .widgetAccentable()
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(accessibilityValue)
    }

    private var gaugeTint: Gradient {
        Gradient(colors: [WatchTheme.alarm, WatchTheme.caution, WatchTheme.healthy])
    }

    private var accessibilityText: String {
        guard let summary else { return "No colony" }
        // A decision is the one thing worth saying first; the gauge is the
        // value behind it either way.
        if let decision = summary.decision { return decision.title }
        return summary.gauge.meaning.label
    }

    private var accessibilityValue: String {
        guard let summary else { return "Open FlowerPower on iPhone" }
        if let decision = summary.decision {
            return "\(decision.detail). \(summary.gauge.meaning.label): \(summary.gauge.caption)"
        }
        return "\(summary.gauge.caption). \(summary.shortHeadline)"
    }
}

private struct CornerView: View {

    let summary: WatchSummary?

    var body: some View {
        Image(systemName: summary?.decision?.kind.symbolName ?? "hexagon.fill")
            .widgetLabel {
                Gauge(value: summary?.gauge.value ?? 0) {
                    // The corner's label is a few characters wide, so the
                    // decision's short title displaces the gauge's.
                    Text(summary?.decision?.title ?? summary?.gauge.meaning.label ?? "Hive")
                }
                .tint(summary?.hasDecision == true ? WatchTheme.alarm : WatchTheme.honey)
            }
            .widgetAccentable()
            .accessibilityLabel(summary?.gauge.meaning.label ?? "Hive")
            .accessibilityValue(summary?.gauge.caption ?? "No colony")
    }
}

private struct InlineView: View {

    let summary: WatchSummary?

    var body: some View {
        if let decision = summary?.decision {
            Label(decision.title, systemImage: decision.kind.symbolName)
        } else if let summary {
            Label("\(summary.shortHeadline) · \(summary.population) bees", systemImage: "hexagon.fill")
        } else {
            Label("No colony", systemImage: "hexagon")
        }
    }
}

private struct RectangularView: View {

    let summary: WatchSummary?

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: summary.decision?.kind.symbolName ?? summary.status.symbolName)
                    Text(summary.decision?.title ?? summary.shortHeadline)
                        .font(.headline)
                        .lineLimit(1)
                }
                .widgetAccentable()

                // This family has a second line, so it can say what the
                // colony is asking rather than only that it is asking.
                Text(decisionSubtitle ?? summary.gauge.meaning.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Gauge(value: summary.gauge.value) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(summary.hasDecision ? WatchTheme.alarm : WatchTheme.honey)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        } else {
            Label("Open FlowerPower on iPhone", systemImage: "hexagon")
                .font(.caption)
        }
    }

    /// How long there is to answer, or the question itself where there is no
    /// countdown to give.
    private var decisionSubtitle: String? {
        guard let decision = summary?.decision else { return nil }
        guard let days = decision.daysRemaining else { return decision.detail }
        switch days {
        case ..<1: return "Decided today"
        case 1: return "1 day to decide"
        default: return "\(days) days to decide"
        }
    }

    private var accessibilityText: String {
        guard let summary else { return "No colony" }
        if let decision = summary.decision {
            return "\(decision.title). \(decisionSubtitle ?? decision.detail)"
        }
        return "\(summary.shortHeadline). \(summary.gauge.meaning.label): \(summary.gauge.caption)"
    }
}

// MARK: - Widget

@main
struct HiveComplication: Widget {

    let kind = "HiveComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HiveProvider()) { entry in
            HiveComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Hive")
        .description("How your colony is doing, and what it needs.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}
