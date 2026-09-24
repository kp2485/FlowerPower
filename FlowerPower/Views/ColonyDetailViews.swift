//
//  ColonyDetailViews.swift
//  FlowerPower
//
//  What is behind a tile.
//
//  The dashboard's tiles say one number each, which is the right amount for a
//  glance and not enough to understand anything. These are the pages they open:
//  the full-size section that used to sit unfurled on the dashboard, unchanged
//  and reused rather than rewritten, with two things added that it never had
//  room for.
//
//  The first is a sentence or two saying what the numbers mean. A colony is a
//  superorganism with about nine readings worth watching, and every one of them
//  is a thing a beekeeper knows and a player has no reason to. "Comb occupancy:
//  94%" is not information until somebody says that a colony with nowhere left
//  to put anything raises swarm cells within the week.
//
//  The second is the shape of the number over time, where the record holds it.
//  `HistoryView` has the full set with a range picker; these are the same
//  charts, drawn the same way, looking back two months — because the question a
//  tile raises is almost always "is that going up or down", and answering it
//  should not mean leaving for another screen.
//

import SwiftUI
import Charts
import FlowerPowerCore
import FlowerPowerGame

// MARK: - Routing

/// A tile's page.
///
/// One view rather than eight destinations registered on the stack, so that the
/// dashboard has a single `navigationDestination` and the tile kind — which is
/// the package's enum, not the view's — is the only thing that has to travel.
///
/// The switch sits in a `Group`, the way `HistoryView` and `GardenView` put
/// their branches, so the body is one view with a builder inside it rather
/// than a bare switch leaning on `body`'s implicit builder. Every page is
/// `private` to this file, like everything else in it: nothing outside needs
/// to name them, and this router is the only way in.
struct ColonyDetailView: View {

    let kind: DashboardSummary.Tile.Kind
    var onPhotograph: () -> Void = {}

    var body: some View {
        Group {
            switch kind {
            case .stores: StoresDetailView()
            case .population: PopulationDetailView()
            case .queen: QueenDetailView()
            case .nest: NestDetailView()
            case .health: HealthDetailView()
            case .honey: HoneyDetailView()
            case .forage: ForageDetailView(onPhotograph: onPhotograph)
            case .record: RecordDetailView()
            }
        }
    }
}

// MARK: - Stores

private struct StoresDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Stores") {
            StoresSection(
                stores: store.snapshot.stores,
                season: store.snapshot.season,
                banked: store.snapshot.honeyTaken
            )

            Explainer(
                "Everything edible in the comb, counted as the honey it is worth. "
                + "The number that decides whether the colony sees spring is the "
                + "gap between what is in there and what the winter will cost — "
                + "and the cost moves, because it is set by the size of the "
                + "cluster that has to be kept alive. A small colony needs less."
            )

            StoresTrace(samples: store.history.recent(60))
        }
    }
}

// MARK: - Population

private struct PopulationDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Population") {
            PopulationSection(population: store.snapshot.population)

            Explainer(
                "A summer worker lives about six weeks and a winter one about six "
                + "months, so the same count means two quite different things in "
                + "July and in October. What is worth watching is the brood: a "
                + "colony with eggs and larvae in it is a colony that will still "
                + "be here in a month, whatever the adults are doing today."
            )

            PopulationTrace(samples: store.history.recent(60))
        }
    }
}

// MARK: - Queen

private struct QueenDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Queen") {
            QueenSection(queen: store.snapshot.queen)

            Explainer(
                "One queen lays every egg in the nest, so everything downstream of "
                + "her — the brood, next month's foragers, the colony's ability to "
                + "replace its losses — is her. She mates once, in the air, with a "
                + "dozen or more drones and never again, and the sperm she stored "
                + "on that flight has to last her life. A queen who mated poorly "
                + "runs out and begins laying only drones, which is the end of the "
                + "colony unless it supersedes her first."
            )

            NavigationLink {
                LineageView()
            } label: {
                Label("The whole line", systemImage: "crown.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.queen)
        }
    }
}

// MARK: - Nest

private struct NestDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Nest") {
            NestConditionSection(nest: store.snapshot.nest)

            Explainer(
                "Brood needs thirty-five degrees, give or take one, and the colony "
                + "holds it there through a January night by shivering — which is "
                + "paid for out of the larder. How flat the nest line stays while "
                + "the outside one swings is the clearest thing a colony does that "
                + "cannot be seen from the entrance. Comb space, meanwhile, is what "
                + "limits how much they can store: a nest with nowhere left to put "
                + "anything raises swarm cells within the week."
            )

            TemperatureTrace(samples: store.history.recent(60))
        }
    }
}

// MARK: - Health

private struct HealthDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Health") {
            HealthSection(health: store.snapshot.health)

            Explainer(
                "Nothing here is treated with anything. The colony's own defences "
                + "are what work on it: hygienic bees uncap infested cells and "
                + "throw the brood out, and how many of them there are comes from "
                + "the queen. A well-mated queen with a dozen fathers behind her "
                + "brood is the difference between a mite load that plateaus and "
                + "one that does not."
            )
        }
    }
}

// MARK: - Honey

private struct HoneyDetailView: View {

    @Environment(GameStore.self) private var store

    var body: some View {
        DetailPage("Honey") {
            HoneyDecisionCard(snapshot: store.snapshot)

            Explainer(
                "The surplus is what they have put away beyond what the coming "
                + "winter needs, in every season. The winter is reckoned for the "
                + "colony as it stands, so at midsummer, with the nest at its "
                + "fullest, the reserve is at its largest; it shrinks as the "
                + "summer bees die off, and the crop is usually taken in autumn. "
                + "Anything taken stays yours: a colony that turns out to be "
                + "short can be given it back."
            )

            IntakeTrace(samples: store.history.recent(60))
        }
    }
}

// MARK: - Forage

private struct ForageDetailView: View {

    @Environment(GameStore.self) private var store
    var onPhotograph: () -> Void

    private var snapshot: ColonySnapshot { store.snapshot }

    /// Everything the bees can actually work today, the player's flowers first
    /// — that is the half of it they can do something about.
    private var working: [ForageLine] {
        snapshot.patches.filter(\.isInBloom).map { ForageLine(patch: $0, isWild: false) }
            + snapshot.wildPatches.filter(\.isInBloom).map { ForageLine(patch: $0, isWild: true) }
    }

    var body: some View {
        DetailPage("Forage") {
            Explainer(
                "A photograph is a stand of flowers, and a stand does not last. A "
                + "patch is at its best for about two months and gone a few months "
                + "after that, so the garden has to be added to rather than "
                + "collected. What grows wild in the country around the nest the "
                + "bees find on their own, and it is theirs whether you go out or "
                + "not."
            )

            if working.isEmpty {
                ContentUnavailableView(
                    "Nothing in bloom",
                    systemImage: "leaf",
                    description: Text(
                        snapshot.season == .winter
                            ? "Two plants flower in winter and both are keystones. It is worth going to look."
                            : "Nothing you have found is in bloom and in range. Photograph something that is."
                    )
                )
                .frame(maxWidth: .infinity)
                .card()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("In bloom", systemImage: "leaf.fill")
                    ForEach(working) { entry in
                        PatchLine(patch: entry.patch, isWild: entry.isWild)
                        if entry.id != working.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }

            Button(action: onPhotograph) {
                Label("Photograph a Flower", systemImage: "camera.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.honey)

            IntakeTrace(samples: store.history.recent(60))
        }
    }
}

/// A stand the bees can work, and whether it is one the player went out and
/// found or one that was simply there.
private struct ForageLine: Identifiable {
    let patch: PatchSummary
    let isWild: Bool
    /// The patch's own identity. A garden patch and a wild one can never share
    /// one — `EntityID`s are unique across the world.
    var id: EntityID { patch.id }
}

/// One stand of flowers, in a line.
private struct PatchLine: View {

    let patch: PatchSummary
    let isWild: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isWild ? "leaf.fill" : "camera.macro")
                .foregroundStyle(isWild ? Theme.wild : Theme.honey)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(patch.speciesName)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(facts)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Only worth saying while it is true. A stand at full vigour
                // needs no comment; one that is going is the cue to go out.
                if patch.isFading {
                    Text(String(format: "%.0f%% of the stand left", patch.vigour * 100))
                        .font(.caption2)
                        .foregroundStyle(Theme.caution)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// How far, who is on it, and whether it is wild, joined with middle
    /// dots. Built as a list of parts rather than one expression of `+` and
    /// ternaries passed to `Text`, which is the shape of expression the type
    /// checker gives up on.
    private var facts: String {
        var parts: [String] = ["\(Int(patch.distanceMetres.rounded())) m"]
        if patch.foragersWorkingIt > 0 {
            parts.append("\(patch.foragersWorkingIt) working it")
        } else {
            parts.append("nobody on it")
        }
        if isWild { parts.append("wild") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Record

private struct RecordDetailView: View {

    @Environment(GameStore.self) private var store

    private var snapshot: ColonySnapshot { store.snapshot }

    var body: some View {
        DetailPage("Record") {
            // The year's account used to appear on the dashboard in winter and
            // nowhere else, which meant that the one thing written to be read
            // was unreachable for three seasons out of four.
            if snapshot.hasSomethingToRead {
                YearInReviewCard(review: snapshot.review(year: snapshot.yearWorthReading))
            }

            RecordLinks()

            Explainer(
                "Five different accounts of the same colony. The lineage is its "
                + "queens; the almanac is what happened and when; the collection "
                + "is every flower you have photographed; the milestones are the "
                + "firsts; and the history is the numbers, charted. The record "
                + "keeps the last two years of days — longer than most colonies "
                + "live."
            )
        }
    }
}

// MARK: - Furniture

/// The shape every detail page has: a scroll of cards on the grouped
/// background, with the tile's own name in the bar.
private struct DetailPage<Content: View>: View {

    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
    }
}

/// What the numbers above it mean.
private struct Explainer: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

// MARK: - The charts

/// Stores against what the winter will cost.
///
/// The same marks `HistoryView` draws, because two charts of one quantity that
/// look different are two quantities as far as anybody reading them is
/// concerned.
private struct StoresTrace: View {

    let samples: [DailySample]

    private var summary: String {
        guard let first = samples.first, let last = samples.last else {
            return "No days recorded."
        }
        let lowest = samples.map(\.edibleEnergy).min() ?? last.edibleEnergy
        let short = last.edibleEnergy < last.winterRequirement
        return "\(samples.count) days. "
            + "Stores from \(Int(first.edibleEnergy.rounded())) to "
            + "\(Int(last.edibleEnergy.rounded())) units, lowest \(Int(lowest.rounded())). "
            + "The winter needs \(Int(last.winterRequirement.rounded())), "
            + "so they are \(short ? "short of it" : "ahead of it")."
    }

    var body: some View {
        TraceCard(
            title: "The last two months",
            symbolName: "drop.fill",
            caption: samples.last.map {
                "\(Int($0.edibleEnergy.rounded())) of \(Int($0.winterRequirement.rounded())) units needed"
            },
            summary: summary,
            samples: samples
        ) {
            Chart {
                ForEach(samples) { sample in
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

/// Adults, brood and winter bees, with the seasons behind them.
private struct PopulationTrace: View {

    let samples: [DailySample]

    private var spans: [SeasonSpan] { SeasonSpan.spans(covering: samples) }

    /// A little headroom over the tallest line, and the same number the season
    /// bands are drawn to — a band has to be given a height, and giving it one
    /// the scale does not share would clip it.
    private var ceiling: Double {
        let tallest = samples.map { Double(max($0.adults, $0.brood)) }.max() ?? 1
        return max(10, (tallest * 1.1).rounded(.up))
    }

    private var summary: String {
        guard let first = samples.first, let last = samples.last else {
            return "No days recorded."
        }
        let peak = samples.map(\.adults).max() ?? last.adults
        return "\(samples.count) days. "
            + "Adults from \(first.adults) to \(last.adults), at most \(peak). "
            + "Brood from \(first.brood) to \(last.brood). "
            + "\(last.winterBees) winter bees now."
    }

    var body: some View {
        TraceCard(
            title: "The last two months",
            symbolName: "person.3.fill",
            caption: samples.last.map { "\($0.adults) adults, \($0.brood) brood" },
            summary: summary,
            samples: samples
        ) {
            Chart {
                // A colony halving in size is alarming in June and is simply
                // what October looks like, so the season goes behind the line.
                ForEach(spans) { span in
                    RectangleMark(
                        xStart: .value("From", Double(span.firstDay) - 0.5),
                        xEnd: .value("To", Double(span.lastDay) + 0.5),
                        yStart: .value("Bees", 0.0),
                        yEnd: .value("Bees", ceiling)
                    )
                    .foregroundStyle(Theme.colour(for: span.season).opacity(0.14))
                }

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

/// The nest against the weather outside.
private struct TemperatureTrace: View {

    let samples: [DailySample]

    private var summary: String {
        guard !samples.isEmpty else { return "No days recorded." }
        let nest = samples.map(\.nestTemperature)
        let outside = samples.map(\.outsideTemperature)
        return "\(samples.count) days. "
            + "The nest held between \(Int((nest.min() ?? 0).rounded())) and "
            + "\(Int((nest.max() ?? 0).rounded())) degrees, against outside "
            + "\(Int((outside.min() ?? 0).rounded())) to "
            + "\(Int((outside.max() ?? 0).rounded())). Brood needs 34."
    }

    var body: some View {
        TraceCard(
            title: "Nest and outside",
            symbolName: "thermometer.medium",
            caption: samples.last.map {
                "\(Int($0.nestTemperature.rounded()))°C in the nest, "
                    + "\(Int($0.outsideTemperature.rounded()))°C outside"
            },
            summary: summary,
            samples: samples
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

/// What came in each day.
private struct IntakeTrace: View {

    let samples: [DailySample]

    private var summary: String {
        guard !samples.isEmpty else { return "No days recorded." }
        let total = samples.reduce(0) { $0 + $1.nectarIntake }
        let best = samples.map(\.nectarIntake).max() ?? 0
        let empty = samples.filter { $0.nectarIntake < 0.5 }.count
        return "\(Int(total.rounded())) units over \(samples.count) days. "
            + "The best day brought in \(Int(best.rounded())), "
            + "and \(empty) days brought in nothing."
    }

    var body: some View {
        TraceCard(
            title: "Nectar brought in",
            symbolName: "arrow.down.to.line",
            caption: samples.last.map { "\(Int($0.nectarIntake.rounded())) units on the last full day" },
            summary: summary,
            samples: samples
        ) {
            Chart(samples) { sample in
                BarMark(
                    x: .value("Day", Double(sample.day)),
                    y: .value("Units", sample.nectarIntake)
                )
                .foregroundStyle(Theme.nectar)
            }
        }
    }
}

/// One chart, in the app's card, with the axis treatment they all share.
///
/// A copy of `HistoryView`'s own furniture rather than a shared type, and
/// deliberately: that file is the record's own screen and belongs to it. What
/// is shared is the idiom — the day labels, the leading axis, the chart
/// collapsed to a single accessibility element with the shape of the line read
/// for it, because Swift Charts otherwise publishes several hundred stops that
/// each say a number and none of which says what the chart shows.
private struct TraceCard<Content: View>: View {

    let title: String
    let symbolName: String
    let caption: String?
    let summary: String
    /// Passed in so the card can decide there is nothing to draw. A single day
    /// cannot be a line, and an empty chart with axes on it looks like a bug.
    let samples: [DailySample]
    let content: Content

    init(
        title: String,
        symbolName: String,
        caption: String? = nil,
        summary: String,
        samples: [DailySample],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.caption = caption
        self.summary = summary
        self.samples = samples
        self.content = content()
    }

    var body: some View {
        if samples.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbolName)
                    .font(.subheadline.weight(.semibold))

                if let caption {
                    Text(caption)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                content
                    .frame(height: 160)
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title) chart")
                    .accessibilityValue(summary)

                NavigationLink {
                    HistoryView()
                } label: {
                    Label("The whole record", systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    /// Days are counted from the colony's founding, which past the first year
    /// makes for a number nobody can place. The axis shows the day of the year,
    /// with the year alongside once there is more than one.
    private static func label(forDay day: Int) -> String {
        let dayOfYear = day % Season.daysPerYear + 1
        let year = day / Season.daysPerYear + 1
        return year > 1 ? "\(dayOfYear)/y\(year)" : "\(dayOfYear)"
    }
}
