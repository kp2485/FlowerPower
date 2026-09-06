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

import WidgetKit
import SwiftUI
import ActivityKit
import FlowerPowerCore
import FlowerPowerGame

@main
struct FlowerPowerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HiveWidget()
        HiveActivity()
    }
}

// MARK: - The Home Screen widget

struct HiveWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WatchSummary?
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
                entries.append(HiveWidgetEntry(date: date, summary: simulation.watchSummary(now: date)))
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
        StaticConfiguration(kind: "com.kylepeterson.flowerpower.hive", provider: HiveWidgetProvider()) { entry in
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
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label(summary.shortHeadline, systemImage: summary.status.symbolName)
                        .font(.headline)
                    Text(summary.gauge.caption).font(.caption)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: summary.status.symbolName)
                            .foregroundStyle(WidgetTheme.colour(for: summary.status))
                        Text(summary.status.displayName).font(.headline)
                        Spacer()
                        Image(systemName: WidgetTheme.symbol(for: summary.season))
                            .foregroundStyle(.secondary)
                    }
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
                    HStack {
                        Label("\(summary.population)", systemImage: "hexagon.fill")
                        Label("\(Int(summary.honey.rounded()))", systemImage: "drop.fill")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack {
                Image(systemName: "hexagon")
                Text("No colony yet").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Live Activities

struct HiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HiveActivityAttributes.self) { context in
            // The lock screen.
            HStack(spacing: 14) {
                Image(systemName: context.attributes.symbol)
                    .font(.title2)
                    .foregroundStyle(context.state.decisionOpen ? WidgetTheme.caution : WidgetTheme.honey)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.title).font(.headline)
                    Text(context.state.status).font(.subheadline).foregroundStyle(.secondary)
                    if context.state.posture != "Instinct" {
                        Text(context.state.posture).font(.caption).foregroundStyle(WidgetTheme.healthy)
                    }
                }
                Spacer()
                if let progress = context.state.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .frame(width: 32, height: 32)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbol)
                        .font(.title2)
                        .foregroundStyle(WidgetTheme.honey)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.daysRemaining)d")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status).font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol)
            } compactTrailing: {
                Text("\(context.state.daysRemaining)d").monospacedDigit()
            } minimal: {
                Image(systemName: context.attributes.symbol)
            }
        }
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

    static func symbol(for season: Season) -> String {
        switch season {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }
}
