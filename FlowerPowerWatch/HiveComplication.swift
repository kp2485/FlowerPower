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
            if let summary {
                Image(systemName: summary.status.symbolName)
            } else {
                Image(systemName: "hexagon")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeTint)
        .widgetAccentable()
        .accessibilityLabel(accessibilityText)
    }

    private var gaugeTint: Gradient {
        Gradient(colors: [WatchTheme.alarm, WatchTheme.caution, WatchTheme.healthy])
    }

    private var accessibilityText: String {
        guard let summary else { return "No colony" }
        return "\(summary.gauge.meaning.label): \(summary.gauge.caption). \(summary.shortHeadline)"
    }
}

private struct CornerView: View {

    let summary: WatchSummary?

    var body: some View {
        Image(systemName: "hexagon.fill")
            .widgetLabel {
                Gauge(value: summary?.gauge.value ?? 0) {
                    Text(summary?.gauge.meaning.label ?? "Hive")
                }
                .tint(WatchTheme.honey)
            }
            .widgetAccentable()
    }
}

private struct InlineView: View {

    let summary: WatchSummary?

    var body: some View {
        if let summary {
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
                    Image(systemName: summary.status.symbolName)
                    Text(summary.shortHeadline)
                        .font(.headline)
                        .lineLimit(1)
                }
                .widgetAccentable()

                Text(summary.gauge.meaning.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Gauge(value: summary.gauge.value) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(WatchTheme.honey)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.shortHeadline). \(summary.gauge.meaning.label): \(summary.gauge.caption)")
        } else {
            Label("Open FlowerPower on iPhone", systemImage: "hexagon")
                .font(.caption)
        }
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
