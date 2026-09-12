//
//  HistoryView.swift
//  FlowerPower
//
//  The colony's numbers over time.
//
//  The dashboard answers "how is the colony now"; the almanac answers "what
//  happened". Neither answers "is it getting better", which is the question a
//  keeper opening their records actually has. Four charts, all off one record
//  kept in the package: the population with the seasons behind it, the stores
//  against what the winter will cost, the nest against the weather outside,
//  and what came in each day.
//
//  Everything selected, banded or derived here is computed in
//  `FlowerPowerCore`'s `History.swift` — the ranges, the season runs, the
//  readiness — so this file only draws.
//

import SwiftUI
import Charts
import FlowerPowerCore
import FlowerPowerGame

struct HistoryView: View {

    @Environment(GameStore.self) private var store
    @State private var range: HistoryRange = .month

    private var history: ColonyHistory { store.history }
    private var today: Int { store.snapshot.day }

    /// The days on the page.
    private var samples: [DailySample] {
        history.samples(in: range, endingOn: today)
    }

    /// A single day cannot be a line. The empty state stands until there are
    /// two of them, which is the morning of the colony's second day.
    private var hasEnoughToChart: Bool { samples.count >= 2 }

    var body: some View {
        Group {
            if history.samples.count < 2 {
                ContentUnavailableView(
                    "Nothing to chart yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("The colony is recorded once a day. Come back tomorrow and there will be a line.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        RangePicker(range: $range, history: history, today: today)

                        if hasEnoughToChart {
                            PopulationChart(samples: samples)
                            StoresChart(samples: samples)
                            TemperatureChart(samples: samples)
                            IntakeChart(samples: samples)
                            RecordFootnote(history: history)
                        } else {
                            Text("Not enough of this range has been lived through yet. Try a longer one.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("History")
    }
}

// MARK: - Range

private struct RangePicker: View {

    @Binding var range: HistoryRange
    let history: ColonyHistory
    let today: Int

    var body: some View {
        Picker("Range", selection: $range) {
            // Only the ranges the record can actually fill, so a colony three
            // weeks old is not offered a year of nothing.
            ForEach(HistoryRange.allCases.filter { history.offers($0, endingOn: today) }) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Population

private struct PopulationChart: View {

    let samples: [DailySample]

    private var spans: [SeasonSpan] { SeasonSpan.spans(covering: samples) }

    /// A little headroom over the tallest line, and the same number the season
    /// bands are drawn to — a band has to be given a height, and giving it one
    /// the scale does not share would clip it.
    private var ceiling: Double {
        let tallest = samples.map { Double(max($0.adults, $0.brood)) }.max() ?? 1
        return max(10, (tallest * 1.1).rounded(.up))
    }

    var body: some View {
        ChartCard(
            title: "Population",
            symbolName: "person.3.fill",
            caption: samples.last.map { "\($0.adults) adults, \($0.brood) brood" }
        ) {
            Chart {
                SeasonBands(spans: spans, ceiling: ceiling)

                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Bees", Double(sample.adults)),
                        series: .value("Series", "Adults")
                    )
                    .foregroundStyle(by: .value("Series", "Adults"))

                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Bees", Double(sample.brood)),
                        series: .value("Series", "Brood")
                    )
                    .foregroundStyle(by: .value("Series", "Brood"))

                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Bees", Double(sample.winterBees)),
                        series: .value("Series", "Winter bees")
                    )
                    .foregroundStyle(by: .value("Series", "Winter bees"))
                }
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...ceiling)
            .chartForegroundStyleScale([
                "Adults": Theme.honey,
                "Brood": Theme.broodNest,
                "Winter bees": Theme.propolis
            ])
        }
    }
}

/// The seasons, drawn behind everything else.
///
/// A colony halving in size is alarming in June and is simply what October
/// looks like, and no population chart is readable without knowing which one
/// it is showing. The half-day either side makes a band cover the whole width
/// of the days it holds rather than stopping at their centres; the height is
/// passed in rather than left to the chart, because every bound of a
/// `RectangleMark` has to be given for its type to be inferred.
private struct SeasonBands: ChartContent {

    let spans: [SeasonSpan]
    let ceiling: Double

    var body: some ChartContent {
        ForEach(spans) { span in
            RectangleMark(
                xStart: .value("From", Double(span.firstDay) - 0.5),
                xEnd: .value("To", Double(span.lastDay) + 0.5),
                yStart: .value("Bees", 0.0),
                yEnd: .value("Bees", ceiling)
            )
            .foregroundStyle(Theme.colour(for: span.season).opacity(0.14))
        }
    }
}

// MARK: - Stores

private struct StoresChart: View {

    let samples: [DailySample]

    var body: some View {
        ChartCard(
            title: "Stores",
            symbolName: "drop.fill",
            caption: samples.last.map {
                "\(Int($0.edibleEnergy.rounded())) of \(Int($0.winterRequirement.rounded())) units needed"
            }
        ) {
            Chart {
                ForEach(samples) { sample in
                    // The stores are the area; the requirement is the line to
                    // stay above. The gap between them is the whole story of
                    // an autumn, and neither on its own says anything.
                    AreaMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Units", sample.edibleEnergy)
                    )
                    .foregroundStyle(Theme.honey.opacity(0.35))

                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Units", sample.edibleEnergy),
                        series: .value("Series", "Stores")
                    )
                    .foregroundStyle(by: .value("Series", "Stores"))

                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Units", sample.winterRequirement),
                        series: .value("Series", "Winter needs")
                    )
                    .foregroundStyle(by: .value("Series", "Winter needs"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale([
                "Stores": Theme.honey,
                "Winter needs": Theme.alarm
            ])
        }
    }
}

// MARK: - Temperature

private struct TemperatureChart: View {

    let samples: [DailySample]

    var body: some View {
        ChartCard(
            title: "Nest and outside",
            symbolName: "thermometer.medium",
            caption: samples.last.map {
                "\(Int($0.nestTemperature.rounded()))°C in the nest, "
                    + "\(Int($0.outsideTemperature.rounded()))°C outside"
            }
        ) {
            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("°C", sample.nestTemperature),
                        series: .value("Series", "Nest")
                    )
                    .foregroundStyle(by: .value("Series", "Nest"))

                    LineMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("°C", sample.outsideTemperature),
                        series: .value("Series", "Outside")
                    )
                    .foregroundStyle(by: .value("Series", "Outside"))
                }
                .interpolationMethod(.monotone)

                // Brood needs 34°C or so. How flat the nest line stays across
                // a cold snap is the colony's thermoregulation, drawn.
                // 34.0 rather than 34: every y value in a chart has to be the
                // same plottable type, and the temperatures are Doubles.
                RuleMark(y: .value("Brood nest", 34.0))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .chartForegroundStyleScale([
                "Nest": Theme.broodNest,
                "Outside": Color(red: 0.36, green: 0.65, blue: 0.85)
            ])
        }
    }
}

// MARK: - Intake

private struct IntakeChart: View {

    let samples: [DailySample]

    var body: some View {
        ChartCard(
            title: "Nectar brought in",
            symbolName: "arrow.down.to.line",
            caption: samples.last.map { "\(Int($0.nectarIntake.rounded())) units on the last full day" }
        ) {
            Chart(samples) { sample in
                // A bar a day reads well for a month and turns into a smear
                // for a year, so a long range is filled instead.
                if samples.count > 90 {
                    AreaMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Units", sample.nectarIntake)
                    )
                    .foregroundStyle(Theme.nectar.gradient)
                } else {
                    BarMark(
                        x: .value("Day", Double(sample.day)),
                        y: .value("Units", sample.nectarIntake)
                    )
                    .foregroundStyle(Theme.nectar)
                }
            }
        }
    }
}

// MARK: - Furniture

/// One chart, in the app's card, with the axis treatment they all share.
private struct ChartCard<Content: View>: View {

    let title: String
    let symbolName: String
    let caption: String?
    let content: Content

    init(
        title: String,
        symbolName: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))

            if let caption {
                Text(caption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            content
                .frame(height: 170)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let day = value.as(Double.self) {
                                Text(Self.label(forDay: Int(day.rounded())))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Days are counted from the colony's founding, which past the first year
    /// makes for a number nobody can place. The axis shows the day of the
    /// year, with the year alongside once there is more than one.
    private static func label(forDay day: Int) -> String {
        let dayOfYear = day % Season.daysPerYear + 1
        let year = day / Season.daysPerYear + 1
        return year > 1 ? "\(dayOfYear)/y\(year)" : "\(dayOfYear)"
    }
}

/// How far back the record goes, said plainly, because the cap is real and a
/// player looking at a three-year-old colony should know why year one is gone.
private struct RecordFootnote: View {

    let history: ColonyHistory

    var body: some View {
        if let first = history.firstDay, let last = history.lastDay {
            Text("Recorded from day \(first + 1) to day \(last + 1). "
                 + "The colony keeps the last \(ColonyHistory.limit) days.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
