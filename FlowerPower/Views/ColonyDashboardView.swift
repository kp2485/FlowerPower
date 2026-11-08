//
//  ColonyDashboardView.swift
//  FlowerPower
//
//  The screen that answers "how are my bees?" — and, when the answer is "not
//  well", says what to do about it.
//
//  It used to answer at length. A column of full-size cards, every one of them
//  unfurled whether or not anything in it had moved, so that reading the colony
//  meant scrolling past nine sections to find the one number that had. An
//  overview that does not fit on a screen is not an overview; it is a report,
//  and nobody reads a report four times a day.
//
//  Then it was a grid of eight tiles, which fitted better and still asked the
//  player to know which of the eight belonged together. Now it is four cards,
//  two abreast — the bees, the larder, inside, outside — each a short list of
//  one-line readings: a symbol, what it is, one number, and a colour that
//  says how worried to be. Every line is a way in: a reading opens the
//  full-size page it stands for, in `ColonyDetailViews.swift`, and a place
//  (the jobs, the comb, the country, the garden) opens the tab that draws it.
//  What a line says, how worried it looks and which card it sits in is
//  `DashboardSummary` in the package, tested there without a Mac; this file
//  only draws it.
//
//  The whole of it fits on one screen without scrolling at the ordinary text
//  sizes, which is the rule the layout is held to: the record went into the
//  header as the day, and the bloom prompt — which used to be a card at the
//  foot and the one thing always below the fold — is a line in Outside that
//  opens the Forage page, where the card now lives.
//
//  How many cards sit abreast comes from the width and the text size, not
//  from the device: the minimum card width is a `@ScaledMetric`, so a phone
//  gets two columns, an iPad four, and larger text buys fewer without a rule
//  saying so. At the accessibility sizes the lines lose their captions and
//  keep their titles (`DashboardSummary.Density`), the number drops under the
//  title, and the screen scrolls, as it should. The symbol tier — a glyph and
//  a number — is the watch's, in `WatchRootView`; the phone never picks it
//  for large text, because somebody who turns the text up is asking to read.
//
//  When the whole page fits, it is not a scroll view at all: the cards
//  stretch to fill what is left, their lines growing together up to a cap,
//  so the grid ends where the screen does instead of over a blank strip —
//  and because every card has three lines, their edges meet. Only when it
//  does not fit (large text, several decisions open) does `ViewThatFits`
//  fall back to scrolling. A wide screen, where four cards abreast leave the
//  bottom half empty, gets a second row: the bloom prompt and the two charts
//  a player opens most.
//
//  Decisions keep their place at the top, because a decision has a window and a
//  window nobody saw is an answer given by silence. They are collapsed to one
//  row apiece, and the card that used to sit open on the page opens in a sheet
//  instead — the same card, unrestructured, so the phone and the watch and the
//  notification still describe the question in the same words.
//

import SwiftUI
import TipKit
import FlowerPowerCore
import FlowerPowerGame

struct ColonyDashboardView: View {

    @Environment(GameStore.self) private var store
    var onPhotograph: () -> Void
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.likelyHere.rawValue
    @State private var isRelocating = false
    /// Set by the swarm card's "move" button. The decision sheet has to be
    /// gone before the site picker can come up, so the move waits for it.
    @State private var relocateOnceClosed = false

    /// What the player has opened.
    ///
    /// A path the view owns rather than a set of plain destination links, for
    /// one reason: the long-press menu on a tile has to be able to push the
    /// same page the tap does, and a menu item cannot tap a `NavigationLink`.
    /// It also gives the haptic something to fire on — `path.count` changes
    /// exactly when a tile opens, whichever way it was opened.
    @State private var path = NavigationPath()

    /// The decision showing in the sheet, if any.
    @State private var openDecision: DecisionKind?

    /// Whether the attention row is showing what is under it.
    @State private var showingAlerts = false

    private var snapshot: ColonySnapshot { store.snapshot }

    /// Rebuilt on every draw, which is affordable: it is a dozen comparisons
    /// and a week of the record, against a snapshot that is itself rebuilt
    /// twenty times a minute.
    private var summary: DashboardSummary {
        DashboardSummary(
            snapshot: snapshot,
            history: store.history,
            hemisphere: Hemisphere(rawValue: hemisphereRaw) ?? .northern
        )
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// What a card must be given to be worth drawing. Scaled with the text,
    /// so the columns fall away as the text grows: two on a phone at the
    /// default size, one from two steps up; four on an iPad.
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth: CGFloat = 160

    /// How tall a line may grow when the page has room to give. About half
    /// as much again as it needs, which fills a phone with nothing open and
    /// stops short of lines with a finger's width of nothing in each.
    @ScaledMetric(relativeTo: .body) private var lineCap: CGFloat = 68

    /// The width the cards have to share, read once at the page.
    @State private var contentWidth: CGFloat = 0

    private var density: DashboardSummary.Density {
        DashboardSummary.density(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var columnCount: Int {
        DashboardSummary.columns(fitting: contentWidth, minimumCardWidth: minimumCardWidth)
    }

    var body: some View {
        NavigationStack(path: $path) {
            // The page as it fits, or the page as it scrolls. `ViewThatFits`
            // measures the first at its natural height and takes it when
            // that is within the screen, then lays it out to the whole
            // screen, which is what lets the cards stretch.
            ViewThatFits(in: .vertical) {
                page(filling: true)
                ScrollView {
                    page(filling: false)
                }
            }
            // The page's width, not a `GeometryReader` round each card: one
            // reading, at the one place the width is decided.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                contentWidth = width
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Colony")
            // Inline, so that the overview is the one screen it says it is:
            // a large title cost the last section its place above the fold.
            // The status card under it is the real header.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DashboardSummary.Tile.Kind.self) { kind in
                ColonyDetailView(kind: kind, onPhotograph: onPhotograph)
            }
            .sensoryFeedback(.selection, trigger: path.count)
            .sheet(item: $openDecision, onDismiss: {
                guard relocateOnceClosed else { return }
                relocateOnceClosed = false
                isRelocating = true
            }) { kind in
                DecisionSheet(kind: kind, snapshot: snapshot, onRelocate: {
                    relocateOnceClosed = true
                    openDecision = nil
                }) { openDecision = nil }
                .childSheet()
            }
            .sheet(isPresented: $isRelocating) {
                NewColonyView(
                    reason: .relocating,
                    currentSite: snapshot.nest.siteType,
                    largerOnly: true
                ) { site in
                    store.relocateHive(to: HiveLocation(type: site))
                    isRelocating = false
                }
                .childSheet()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onPhotograph) {
                        Label("Photograph a Flower", systemImage: "camera.fill")
                    }
                    .popoverTip(AppTips.photograph)
                }
            }
        }
    }
}

extension ColonyDashboardView {

    /// Everything on the page, top to bottom. `filling` is the version that
    /// is not in a scroll view: it ends in a spacer, so that once the lines
    /// have grown to their cap whatever is left stays at the foot rather than
    /// opening gaps between the cards.
    fileprivate func page(filling: Bool) -> some View {
        VStack(spacing: 12) {
            StatusHeader(snapshot: snapshot, record: summary.tile(.record))

            // Decisions first, and first by a clear margin: everything below
            // this is a thing to know, and these are the only things to do.
            DecisionRows(snapshot: snapshot, open: $openDecision)

            if !summary.attention.isEmpty {
                AttentionRow(
                    attention: summary.attention,
                    alerts: snapshot.alerts,
                    isExpanded: $showingAlerts
                )
            }

            sectionColumns

            if columnCount >= 3 {
                wideExtras
            }

            if filling {
                Spacer(minLength: 0)
            }
        }
        // The page's own width is what the columns are fitted to; the
        // padding comes off before they see it.
        .padding()
    }

    /// What a wide screen does with the room under four cards: the bloom
    /// prompt, which the phone keeps on the Forage page, and the two charts
    /// behind the lines a player opens most.
    fileprivate var wideExtras: some View {
        HStack(alignment: .top, spacing: 12) {
            BloomPromptCard(prompt: BloomPrompt(
                hemisphere: Hemisphere(rawValue: hemisphereRaw) ?? .northern,
                patches: snapshot.patches,
                terrain: snapshot.terrain,
                wildPatches: snapshot.wildPatches
            ), onPhotograph: onPhotograph)
            .frame(maxWidth: .infinity, alignment: .top)

            PopulationTrace(samples: store.history.recent(60))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            StoresTrace(samples: store.history.recent(60))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The row is as tall as the bloom prompt, and the charts fill it.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The four cards, as many abreast as the width allows, dealt into the
    /// columns in turn so each column packs tight and the bottoms differ by
    /// at most a line. `VStack`s rather than a `LazyVGrid`, whose rows are as
    /// tall as their taller card and left a card with a blank third.
    ///
    /// The padding is 32 points of the width it measured, so the cards see
    /// about 370 on an iPhone 17 and 800 on an 11-inch iPad.
    fileprivate var sectionColumns: some View {
        let columns = DashboardSummary.distribute(summary.sections, across: columnCount)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, sections in
                column(of: sections)
            }
        }
    }

    private func column(of sections: [DashboardSummary.Section]) -> some View {
        VStack(spacing: 12) {
            ForEach(sections) { section in
                OverviewSection(
                    section: section,
                    snapshot: snapshot,
                    density: density,
                    lineCap: lineCap,
                    path: $path
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - A section

/// One heading and the lines under it.
///
/// A heading is a word or two in small capitals, the way a grouped list titles
/// its groups, and when the worst line under it is a worry a dot in that
/// line's colour sits beside it — so the four headings can be skimmed before
/// any line is read. The lines sit in one card, divided, and read worst-first:
/// readings before places.
private struct OverviewSection: View {

    let section: DashboardSummary.Section
    let snapshot: ColonySnapshot
    let density: DashboardSummary.Density
    /// How tall a line may be stretched to when the page has room.
    let lineCap: CGFloat
    @Binding var path: NavigationPath

    private var tint: Color { Theme.colour(forDashboard: section.severity) }

    /// What the dot means, for VoiceOver.
    private var verdict: String? {
        switch section.severity {
        case .calm, .notable: return nil
        case .caution: return "worth a look"
        case .alarm: return "needs attention"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let verdict {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(verdict)
                }
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().padding(.leading, 37)
                    }
                    line(for: entry)
                        // Flexible up to the cap, so a page with room to
                        // give stretches every line alike; in a scroll view
                        // nothing proposes the room and the line stays its
                        // natural height.
                        .frame(maxHeight: lineCap)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        }
    }

    /// Which kind of line. Each case is a view of its own, so the builder
    /// holds two plain calls.
    @ViewBuilder
    private func line(for entry: DashboardSummary.Entry) -> some View {
        switch entry {
        case .tile(let tile):
            ReadingLine(tile: tile, snapshot: snapshot, density: density, path: $path)
        case .place(let place):
            PlaceLine(place: place, density: density)
        }
    }
}

/// A reading: symbol, what it is, one number, and the page behind it.
///
/// Everything here arrives already decided. The view picks no thresholds and
/// formats no numbers — if a line is amber it is because `DashboardSummary`
/// said so, and that judgement has a test with a name.
private struct ReadingLine: View {

    let tile: DashboardSummary.Tile
    let snapshot: ColonySnapshot
    let density: DashboardSummary.Density
    @Binding var path: NavigationPath

    private var tint: Color { Theme.colour(forDashboard: tile.severity) }

    var body: some View {
        NavigationLink(value: tile.kind) {
            OverviewLine(
                symbolName: tile.symbolName,
                symbolTint: tint,
                title: tile.title,
                caption: tile.caption,
                headline: tile.headline,
                // A calm number is just a number. One that is anything else
                // takes the colour, so the eye lands on it from the heading.
                headlineTint: tile.severity == .calm ? nil : tint,
                trend: tile.trend,
                density: density
            )
        }
        .buttonStyle(PressableLineStyle())
        .contextMenu {
            Button {
                path.append(tile.kind)
            } label: {
                Label("Open \(tile.title)", systemImage: "chevron.right")
            }
        } preview: {
            TilePreview(tile: tile, snapshot: snapshot)
        }
        // One element with a label and a value, so VoiceOver says "Stores, 82
        // percent of what winter needs" rather than reading four fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.spoken)
        .accessibilityHint("Opens \(tile.title.lowercased())")
    }
}

/// A place: the same line, and the tab that draws it behind it.
private struct PlaceLine: View {

    let place: DashboardSummary.Place
    let density: DashboardSummary.Density
    @Environment(\.openTab) private var openTab

    private var tab: ContentView.Tab {
        switch place.kind {
        case .jobs, .comb: return .nest
        case .country: return .world
        }
    }

    var body: some View {
        Button {
            openTab(tab)
        } label: {
            OverviewLine(
                symbolName: place.symbolName,
                symbolTint: Theme.honey,
                title: place.title,
                caption: place.caption,
                headline: place.headline,
                headlineTint: nil,
                trend: nil,
                density: density
            )
        }
        .buttonStyle(PressableLineStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place.title)
        .accessibilityValue(place.spoken)
        .accessibilityHint("Opens the \(place.title) tab")
    }
}

/// The one shape every line has.
private struct OverviewLine: View {

    let symbolName: String
    let symbolTint: Color
    let title: String
    let caption: String
    let headline: String
    let headlineTint: Color?
    let trend: DashboardSummary.Trend?
    /// How much of the line to draw. The spoken value is the whole of it
    /// whatever this says; see the callers' accessibility values.
    let density: DashboardSummary.Density

    /// The number shares the title's row in half a screen's width, and drops
    /// under the title at the accessibility sizes, where there is no room
    /// beside it.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The symbol's column grows with the text, or at the accessibility
    /// sizes three bees spilled over the words beside them.
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 22

    private var titleRow: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbolName)
                .font(.subheadline)
                .foregroundStyle(symbolTint)
                .frame(width: symbolWidth)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                titleRow {
                    // A step under the number, so that "Population" and
                    // "366" share half a screen without one of them being
                    // cut to "Popula…".
                    if density.showsTitle {
                        Text(title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }

                    // The trend goes with the number it is about; a steady
                    // count draws no arrow at all.
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(headline)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(headlineTint ?? Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let trend, trend != .steady {
                            Image(systemName: trend.symbolName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }

                if density.showsCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // Fills the line, so the chevron is at the edge however the
            // title row is laid out; stacked, nothing else pushes it there.
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// A line pressed dims rather than shrinks: it sits flush against its
/// neighbours in one card, and a line scaling down inside a card looks like
/// the card is breaking.
private struct PressableLineStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.08 : 0)
            )
    }
}

/// What a long press shows without going anywhere.
///
/// Three of the tiles have a breakdown that is worth a look and not worth a
/// page — which resource is short, how the brood is shaped, what the nest is
/// holding — and a peek at those is the cheapest interaction on the screen.
/// The rest show the sentence VoiceOver would read, which is by construction
/// the most that could be said about them in one line.
private struct TilePreview: View {

    let tile: DashboardSummary.Tile
    let snapshot: ColonySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tile.title, systemImage: tile.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.colour(forDashboard: tile.severity))

            breakdown
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }

    /// Which breakdown, and nothing else. Each case is one view of its own,
    /// so the switch holds no declarations and no layout and the type checker
    /// has four plain calls to look at rather than four subtrees.
    @ViewBuilder
    private var breakdown: some View {
        switch tile.kind {
        case .stores:
            StoresPeek(stores: snapshot.stores)
        case .population:
            PopulationPeek(population: snapshot.population)
        case .nest:
            NestPeek(nest: snapshot.nest)
        default:
            Text(tile.spoken)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What is in the larder, one small tile per resource.
private struct StoresPeek: View {

    let stores: StoresSummary

    private var ordered: [ResourceKind] {
        ResourceKind.allCases.filter { (stores.resources[$0] ?? 0) > 0.5 }
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), spacing: 8)],
            spacing: 8
        ) {
            ForEach(ordered, id: \.self) { kind in
                ResourceTile(kind: kind, amount: stores.resources[kind] ?? 0)
            }
        }
    }
}

/// The three counts, and the shape of the brood.
private struct PopulationPeek: View {

    let population: PopulationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                CountPill(value: population.adults, label: "Adults")
                CountPill(value: population.brood, label: "Brood")
                CountPill(value: population.drones, label: "Drones")
            }
            BroodBar(population: population)
        }
    }
}

/// Temperature, humidity and room, as three readings.
private struct NestPeek: View {

    let nest: NestSummary

    /// Within two degrees of thirty-five is where brood wants it.
    private var temperatureTint: Color {
        abs(nest.temperatureCelsius - 35) < 2 ? Theme.healthy : Theme.caution
    }

    var body: some View {
        HStack(spacing: 20) {
            ReadingView(
                symbol: "thermometer.medium",
                value: String(format: "%.1f°C", nest.temperatureCelsius),
                label: "Brood nest",
                tint: temperatureTint
            )
            ReadingView(
                symbol: "humidity.fill",
                value: String(format: "%.0f%%", nest.humidity * 100),
                label: "Humidity",
                tint: Theme.colour(for: .water)
            )
            ReadingView(
                symbol: "hexagon.fill",
                value: "\(nest.freeCells)",
                label: "Free cells",
                tint: Theme.comb
            )
        }
    }
}

// MARK: - Decisions, collapsed

/// The decisions the dashboard can be showing.
///
/// A case per question rather than a case per card, because the sheet has to
/// be able to find the question again when it opens: the snapshot is rebuilt
/// constantly, and a sheet holding a stale `ActiveThreat` would be answering
/// a siege that ended yesterday.
enum DecisionKind: String, Identifiable, Hashable {

    case threat
    case swarm
    case departed
    case entrance
    case feed
    case scout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threat: return "At the Nest"
        case .swarm: return "Swarming"
        case .departed: return "A Swarm Has Left"
        case .entrance: return "The Entrance"
        case .feed: return "Short for Winter"
        case .scout: return "Scouts"
        }
    }
}

/// One row per open decision, in the order they used to be stacked in.
private struct DecisionRows: View {

    let snapshot: ColonySnapshot
    @Binding var open: DecisionKind?

    /// Six rows, each of which may be absent. Every one is a property of its
    /// own with its type written out, so the body is six plain expressions:
    /// six `if`s in one builder, two of them binding and one of them with a
    /// comma condition, is the shape that makes the type checker give up.
    /// `Optional` is a `View` when what it wraps is, and draws nothing when
    /// it is nil.
    var body: some View {
        VStack(spacing: 8) {
            threatRow
            swarmRow
            departedRow
            entranceRow
            feedRow
            scoutRow
        }
    }

    private var threatRow: DecisionRow? {
        guard let threat = snapshot.activeThreat else { return nil }
        return DecisionRow(
            kind: .threat,
            title: "\(threat.predator.displayName) at the nest",
            detail: remaining(threat),
            symbolName: Theme.symbol(for: threat.predator),
            tint: Theme.alarm,
            open: $open
        )
    }

    private var swarmRow: DecisionRow? {
        guard let swarm = snapshot.pendingSwarm else { return nil }
        let title: String = swarm.discouraged
            ? "Making room — it may still go"
            : "Preparing to swarm"
        return DecisionRow(
            kind: .swarm,
            title: title,
            detail: days(swarm.daysRemaining(on: snapshot.day)),
            symbolName: "arrow.triangle.branch",
            tint: Theme.caution,
            open: $open
        )
    }

    private var departedRow: DecisionRow? {
        guard snapshot.departedSwarm != nil else { return nil }
        return DecisionRow(
            kind: .departed,
            title: "A swarm has left",
            detail: "stay, follow, or give it away",
            symbolName: "bird.fill",
            tint: Theme.queen,
            open: $open
        )
    }

    private var entranceRow: DecisionRow? {
        guard snapshot.entranceDecisionOpen else { return nil }
        return DecisionRow(
            kind: .entrance,
            title: "Autumn: the entrance",
            detail: "seal it or keep it open",
            symbolName: "door.left.hand.closed",
            tint: Theme.propolis,
            open: $open
        )
    }

    /// Short for winter, with honey of theirs in the bank. The engine decides
    /// when this is open — the same judgement the winter-stores alert is
    /// raised from — so this asks rather than working it out again.
    private var feedRow: DecisionRow? {
        guard snapshot.feedDecisionOpen else { return nil }
        return DecisionRow(
            kind: .feed,
            title: "They are short for winter",
            detail: "\(Int(snapshot.storesShortfall.rounded()).counted("unit")) short",
            symbolName: "takeoutbag.and.cup.and.straw.fill",
            tint: Theme.caution,
            open: $open
        )
    }

    /// Last of them, and the only one that arrives while things are going
    /// well: a flow is when a tenth of the force is affordable. Kept on screen
    /// while the party is away so that the answer is reported where the
    /// question was asked.
    private var scoutRow: DecisionRow? {
        guard snapshot.terrain != nil,
              snapshot.scoutDecisionOpen || snapshot.scoutsOut
        else { return nil }
        let out = snapshot.scoutsOut
        let title: String = out ? "The scouts are out" : "Ground they have not seen"
        let detail: String = out
            ? back(in: snapshot.scoutsDaysRemaining)
            : "a tenth of the foragers, for 3 days"
        return DecisionRow(
            kind: .scout,
            title: title,
            detail: detail,
            symbolName: "map.fill",
            tint: Theme.wild,
            open: $open
        )
    }

    private func remaining(_ threat: ActiveThreat) -> String {
        let days = threat.daysRemaining(on: snapshot.day)
        return days <= 0 ? "resolves today" : "\(days) day\(days == 1 ? "" : "s") to decide"
    }

    private func days(_ count: Int) -> String {
        count <= 0 ? "any day now" : "\(count) day\(count == 1 ? "" : "s")"
    }

    private func back(in days: Int?) -> String {
        guard let days, days > 0 else { return "back today" }
        return "back in \(days) day\(days == 1 ? "" : "s")"
    }
}

/// A decision, as a banner: symbol, what it is, how long there is, chevron.
private struct DecisionRow: View {

    let kind: DecisionKind
    let title: String
    let detail: String
    let symbolName: String
    let tint: Color
    @Binding var open: DecisionKind?

    /// "stay, follow, or give it away" is one line at the ordinary sizes and
    /// "stay, follow, or give i…" at the accessibility ones; there it wraps.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            open = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .imageScale(.large)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            // A decision is not a card among cards. The tint behind it is what
            // makes it read as the one thing on the screen to be done.
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PressableTileStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityHint("Opens the decision")
    }
}

/// The full-size card, in a sheet that stops halfway up.
///
/// `ThreatDecisionCard` and the rest are unchanged and unrestructured — they
/// are the same cards that used to sit open on the page, and they remain the
/// one place each question is worded. All this does is find the question again
/// from the current snapshot, so that a card cannot answer a siege that has
/// already ended.
private struct DecisionSheet: View {

    let kind: DecisionKind
    let snapshot: ColonySnapshot
    let onRelocate: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card(for: kind)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The switch only picks; each case's "is it still open" lives in a
    /// builder of its own, so no case of the switch binds anything.
    @ViewBuilder
    private func card(for kind: DecisionKind) -> some View {
        switch kind {
        case .threat: threatCard
        case .swarm: swarmCard
        case .departed: departedCard
        case .entrance: entranceCard
        case .feed: feedCard
        case .scout: scoutCard
        }
    }

    @ViewBuilder
    private var threatCard: some View {
        if let threat = snapshot.activeThreat {
            ThreatDecisionCard(threat: threat, snapshot: snapshot)
        } else {
            Answered()
        }
    }

    @ViewBuilder
    private var swarmCard: some View {
        if let swarm = snapshot.pendingSwarm {
            SwarmDecisionCard(swarm: swarm, snapshot: snapshot, onRelocate: onRelocate)
        } else {
            Answered()
        }
    }

    @ViewBuilder
    private var departedCard: some View {
        if let departed = snapshot.departedSwarm {
            DepartedSwarmCard(swarm: departed)
        } else {
            Answered()
        }
    }

    @ViewBuilder
    private var entranceCard: some View {
        if snapshot.entranceDecisionOpen {
            EntranceDecisionCard(snapshot: snapshot)
        } else {
            Answered()
        }
    }

    @ViewBuilder
    private var feedCard: some View {
        if snapshot.feedDecisionOpen {
            FeedDecisionCard(snapshot: snapshot)
        } else {
            Answered()
        }
    }

    @ViewBuilder
    private var scoutCard: some View {
        // The same test as the banner. A flow that ends with the sheet open
        // left a live "Send Scouts" button that the store refused in silence.
        if let terrain = snapshot.terrain, snapshot.scoutDecisionOpen || snapshot.scoutsOut {
            ScoutDecisionCard(snapshot: snapshot, terrain: terrain)
        } else {
            Answered()
        }
    }
}

/// What is left when the question has stopped being asked.
private struct Answered: View {
    var body: some View {
        Label("That has been answered.", systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

// MARK: - Header

/// The one thing at the top of the screen that is not a line in a section.
///
/// Tighter than it was: the headline has come down from `.title3` to `.callout`
/// and the season, the weather, whether the bees are out and the day have been
/// folded into a single line of chips under it. Nothing has been dropped — the
/// header is the sentence the watch shows and the notification writes, and it
/// is the only part of the screen that says what the colony is *doing* rather
/// than what it has.
///
/// The day is also the way into the record. The record is the one reading
/// that is not about today, and a heading over a single line was a heading
/// over nothing, so "Year 1 · Day 14" at the trailing end of the card opens
/// the lineage, the almanac and the rest.
private struct StatusHeader: View {

    let snapshot: ColonySnapshot
    /// The record tile, for what the day link says to VoiceOver.
    let record: DashboardSummary.Tile?

    /// These rows hold four short things side by side. At the accessibility
    /// sizes that left each a sliver, and "Struggling" broke into three lines
    /// of letters, so they stack instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowLayout {
                Label(snapshot.status.displayName, systemImage: snapshot.status.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.colour(for: snapshot.status))
                    .minimumScaleFactor(0.7)

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                Label(snapshot.season.displayName, systemImage: Theme.symbol(for: snapshot.season))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
            }

            Text(snapshot.headline)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            rowLayout {
                WeatherChip(weather: snapshot.weather)

                Label(
                    snapshot.isForaging ? "Foraging" : "In the nest",
                    systemImage: snapshot.isForaging ? "figure.walk.motion" : "house.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                NavigationLink(value: DashboardSummary.Tile.Kind.record) {
                    HStack(spacing: 3) {
                        Text("Year \(snapshot.year) · Day \(snapshot.displayDay)")
                            .font(.caption2.monospacedDigit())
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record")
                .accessibilityValue(
                    (record?.spoken ?? "Year \(snapshot.year)") + ", day \(snapshot.displayDay)"
                )
                .accessibilityHint("Opens the record")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}

private struct WeatherChip: View {

    let weather: Weather

    var body: some View {
        Label {
            Text("\(Int(weather.temperatureCelsius.rounded()))°C")
                .monospacedDigit()
        } icon: {
            Image(systemName: Theme.symbol(for: weather.sky))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "\(weather.sky.displayName), \(Int(weather.temperatureCelsius.rounded())) degrees"
        )
    }
}

// MARK: - Alerts

/// The alerts, collapsed to one line.
///
/// Six full-size alert cards is the state the dashboard reaches exactly when
/// the player has least appetite for reading six of anything, and it is also
/// the state in which every one of them is pushed off the screen by the others.
/// One row that says how many there are and takes the colour of the worst, and
/// the list itself unfolds in place — in place, rather than on a page of its
/// own, because an alert is three lines long and pushing a whole screen for
/// three lines is the interaction this rebuild is supposed to remove.
private struct AttentionRow: View {

    let attention: DashboardSummary.Attention
    let alerts: [ColonyAlert]
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { Theme.colour(forDashboard: attention.severity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: attention.severity == .alarm
                          ? "exclamationmark.triangle.fill"
                          : "exclamationmark.circle.fill")
                        .foregroundStyle(tint)
                        .imageScale(.large)
                        .accessibilityHidden(true)

                    Text(attention.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(attention.summary)
            .accessibilityHint(isExpanded ? "Hides the list" : "Shows the list")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                ForEach(alerts) { alert in
                    Divider()
                    AlertRow(alert: alert)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sensoryFeedback(.selection, trigger: isExpanded)
    }
}

private struct AlertRow: View {

    let alert: ColonyAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity == .critical
                  ? "exclamationmark.triangle.fill"
                  : "exclamationmark.circle.fill")
                .foregroundStyle(Theme.colour(for: alert.severity))
                .imageScale(.large)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                Text(alert.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion = alert.suggestion {
                    Text(suggestion)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stores

/// The full-size sections, as they always were.
///
/// Internal rather than private now, and that is the whole of the change to
/// them: each one is the body of the page its tile opens, in
/// `ColonyDetailViews.swift`. Rewriting them for the detail screens would have
/// meant two descriptions of the same thing, and the second one would have been
/// wrong about something within a release.
struct StoresSection: View {

    let stores: StoresSummary
    let season: Season
    /// Honey the player has taken and not given back. It is theirs, but it is
    /// also the colony's winter if the colony turns out to need it, so it is
    /// worth seeing beside what is actually in the comb.
    let banked: Double

    @Environment(\.lastLook) private var lastLook
    /// With the text, so "Royal Jelly" keeps a tile it can be read in.
    @ScaledMetric private var tileWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Stores", systemImage: "archivebox.fill")

            // Winter readiness is the number that decides whether the colony
            // sees spring. In every season now: the tile that opens this page
            // leads with "36% of what winter needs" all year, and in spring
            // and summer this page then never said what that was a percentage
            // of, so "60 honey" sat over "0 to spare" unexplained.
            MeterView(
                label: "Winter Stores",
                value: stores.winterReadiness,
                caption: "\(Int(stores.edibleEnergy.rounded())) of \(Int(stores.winterRequirement.rounded())) needed",
                tint: stores.isWinterReady ? Theme.healthy : Theme.caution,
                symbolName: "snowflake"
            )

            if banked >= 1 {
                Label(
                    "\(Int(banked.rounded()).counted("unit")) taken and still yours to give back",
                    systemImage: "arrow.uturn.backward.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            let ordered = ResourceKind.allCases.filter { (stores.resources[$0] ?? 0) > 0.5 }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 12)],
                spacing: 12
            ) {
                ForEach(ordered, id: \.self) { kind in
                    ResourceTile(
                        kind: kind,
                        amount: stores.resources[kind] ?? 0,
                        delta: lastLook.map { (stores.resources[kind] ?? 0) - $0.resource(kind) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ResourceTile: View {

    let kind: ResourceKind
    let amount: Double
    /// How far it has come since the player last looked, when they have been
    /// away long enough for that to be worth saying.
    var delta: Double? = nil

    private var spokenAmount: String {
        "\(kind.displayName): \(Int(amount.rounded()))" + spoken(delta: delta)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: Theme.symbol(for: kind))
                .foregroundStyle(Theme.symbolColour(for: kind))
                .imageScale(.large)
                .accessibilityHidden(true)

            Text(amount, format: .number.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The live tick changes these every few minutes; rolling the
                // digits is what lets the player see the colony working.
                .contentTransition(.numericText(value: amount.rounded()))
                .animation(.snappy, value: amount.rounded())

            if let delta { DeltaChip(delta: delta) }

            Text(kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenAmount)
    }
}

// MARK: - Population

struct PopulationSection: View {

    let population: PopulationSummary

    @Environment(\.lastLook) private var lastLook
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Population", systemImage: "person.3.fill")

            // Four across leaves 70 points each. Two wide gives a five-figure
            // colony somewhere to go at the accessibility sizes.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 0),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
                ),
                spacing: 12
            ) {
                CountPill(value: population.total, label: "Total",
                          delta: lastLook.map { population.total - $0.total })
                CountPill(value: population.adults, label: "Adults",
                          delta: lastLook.map { population.adults - $0.adults })
                CountPill(value: population.brood, label: "Brood",
                          delta: lastLook.map { population.brood - $0.brood })
                CountPill(value: population.drones, label: "Drones",
                          delta: lastLook.map { population.drones - $0.drones })
            }

            BroodBar(population: population)

            if population.winterBees > 0 {
                Label(
                    "\(population.winterBees.counted("winter bee")) — long-lived, and what carries the colony to spring",
                    systemImage: "snowflake"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            MeterView(
                label: "Condition",
                value: population.averageVitality,
                caption: String(format: "%.0f%%", population.averageVitality * 100),
                tint: population.averageVitality > 0.7 ? Theme.healthy : Theme.caution,
                symbolName: "heart.fill"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct CountPill: View {

    let value: Int
    let label: String
    var delta: Int? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            if let delta { DeltaChip(delta: Double(delta)) }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)" + spoken(delta: delta.map(Double.init)))
    }
}

/// Eggs, larvae and pupae as proportions — the shape of the brood nest tells an
/// experienced eye more than the total does.
private struct BroodBar: View {

    let population: PopulationSummary

    fileprivate var segments: [(stage: DevelopmentStage, count: Int)] {
        [(.egg, population.eggs), (.larva, population.larvae), (.pupa, population.pupae)]
            .filter { $0.1 > 0 }
    }

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.count })

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.stage) { segment in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.colour(for: segment.stage))
                            // An egg is the colour of the card in light mode.
                            .strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5)
                            .frame(
                                width: max(2, geometry.size.width
                                          * Double(segment.count) / Double(total) - 2)
                            )
                    }
                }
            }
            .frame(height: 10)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Brood: \(population.eggs.counted("egg")), \(population.larvae.counted("larva", plural: "larvae")), \(population.pupae.counted("pupa", plural: "pupae"))"
        )
    }
}

extension BroodBar {

    @ViewBuilder fileprivate var legend: some View {
        ForEach(segments, id: \.stage) { segment in
            HStack(spacing: 4) {
                Label("\(segment.count)", systemImage: "circle.fill")
                    .labelStyle(LegendLabelStyle(colour: Theme.colour(for: segment.stage)))
                    .font(.caption2)
                Text(segment.stage.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LegendLabelStyle: LabelStyle {
    let colour: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .foregroundStyle(colour)
                .font(.system(size: 7))
            configuration.title
        }
    }
}

// MARK: - Queen

struct QueenSection: View {

    let queen: QueenSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Queen", systemImage: "crown.fill")

            HStack {
                Text(queen.state.displayName)
                    .font(.headline)
                    .foregroundStyle(queen.state == .laying ? Theme.queen : Theme.alarm)
                Spacer()
                if queen.state != .absent, queen.state != .droneLayer || queen.ageDays > 0 {
                    Text("\(queen.ageDays.counted("day")) old")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            if queen.state == .laying || queen.state == .droneLayer {
                MeterView(
                    label: "Genetic Diversity",
                    value: queen.geneticDiversity,
                    caption: queen.patrilines.counted("patriline"),
                    tint: Theme.queen,
                    symbolName: "point.3.connected.trianglepath.dotted"
                )

                MeterView(
                    label: "Hygienic Behaviour",
                    value: queen.hygienicBehaviour,
                    caption: String(format: "%.0f%%", queen.hygienicBehaviour * 100),
                    tint: Theme.healthy,
                    symbolName: "sparkles"
                )

                Text("Diversity comes from how many drones she mated with. It is the colony's main defence against disease.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if queen.daysQueenless > 0 {
                Label("Queenless for \(queen.daysQueenless.counted("day"))", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Theme.alarm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Nest

struct NestConditionSection: View {

    let nest: NestSummary
    let canAffordComb: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Nest", systemImage: "house.fill")

            HStack {
                Text(nest.siteType.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                // Said in words. "66 / 700 cells" over "44 free" left a
                // player to work out that the first is comb built against the
                // room the cavity has, and the second is built comb standing
                // empty.
                Text("\(nest.builtCells) of \(nest.capacity) cells built")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            MeterView(
                label: "Comb in Use",
                value: nest.combOccupancy,
                caption: "\(nest.freeCells) empty",
                tint: nest.combOccupancy > 0.9 ? Theme.caution : Theme.comb,
                symbolName: "hexagon.fill"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { readings }
                VStack(spacing: 12) { readings }
            }

            if !nest.queenCells.isEmpty {
                let names = Set(nest.queenCells.map(\.displayName)).sorted().joined(separator: ", ")
                Label("\(nest.queenCells.count.counted("queen cell")) — \(names)", systemImage: "crown")
                    .font(.caption)
                    .foregroundStyle(Theme.queen)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The room question, before it becomes the swarm question. Only
            // shown once the comb has actually filled the cavity — offering
            // space to a colony with empty frames still in it would be noise.
            if nest.builtCells >= nest.capacity {
                RoomRow(nest: nest, canAffordComb: canAffordComb)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension NestConditionSection {

    @ViewBuilder fileprivate var readings: some View {
        ReadingView(
            symbol: "thermometer.medium",
            value: String(format: "%.1f°C", nest.temperatureCelsius),
            label: "Brood nest",
            tint: abs(nest.temperatureCelsius - 35) < 2 ? Theme.healthy : Theme.caution
        )
        ReadingView(
            symbol: "humidity.fill",
            value: String(format: "%.0f%%", nest.humidity * 100),
            label: "Humidity",
            tint: Theme.colour(for: .water)
        )
        ReadingView(
            symbol: "shield.lefthalf.filled",
            value: String(format: "%.0f%%", nest.propolisEnvelope * 100),
            label: "Propolis",
            tint: Theme.propolis
        )
    }
}

/// What can be done about a nest that has filled its cavity.
private struct RoomRow: View {

    let nest: NestSummary
    let canAffordComb: Bool
    @Environment(GameStore.self) private var store

    /// Counts the times the player has opened the nest up, purely so the
    /// haptic has something to fire on. A trigger value rather than a plain
    /// flag, so it also fires the second time.
    @State private var combAdded = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if nest.siteCanBeExtended {
                Text("The comb has filled the cavity. There is room here for about \(nest.combExtensionRemaining.counted("more cell", plural: "more cells")) — give it to them and they will keep building; leave it and they will divide instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if canAffordComb {
                    Button {
                        if store.addComb() > 0 { combAdded += 1 }
                    } label: {
                        Label("Open the Nest Up", systemImage: "plus.rectangle.on.rectangle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.honey)
                    .sensoryFeedback(.impact(weight: .medium), trigger: combAdded)
                } else {
                    // The same answer the swarm card gives. A button here did
                    // nothing in a dearth and said nothing about why.
                    Label(
                        "Not the honey to draw comb into it yet — wax costs about seven times its weight in stores.",
                        systemImage: "drop.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label(
                    "The cavity is full and there is no more of it.",
                    systemImage: "square.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReadingView: View {

    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Health

struct HealthSection: View {

    let health: HealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Health", systemImage: "cross.case.fill")

            ForEach(health.infections.sorted(by: { $0.value > $1.value }), id: \.key) { pathogen, level in
                MeterView(
                    label: pathogen.displayName,
                    value: level,
                    // A trace as the tile says it. "0%" here, under a tile
                    // reading "<1%", looked like a disease that had gone.
                    caption: level > 0 && level < 0.005
                        ? "a trace"
                        : String(format: "%.0f%%", level * 100),
                    tint: level > 0.5 ? Theme.alarm : Theme.caution,
                    symbolName: "microbe.fill"
                )
            }

            if health.infections[.varroa] != nil {
                Text("Varroa breeds in sealed brood and carries deformed wing virus. Hygienic bees uncap infested cells and remove them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !health.recentAttacks.isEmpty {
                let names = Set(health.recentAttacks.map(\.displayName)).sorted().joined(separator: ", ")
                Label("Recent raids: \(names)", systemImage: "shield.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Shared

struct SectionTitle: View {

    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    ColonyDashboardView(onPhotograph: {})
        .environment(GameStore.preview())
}

// MARK: - The record

/// Lineage, almanac and collection — what a colony leaves behind, and what
/// winter is for reading.
///
/// Five bordered buttons used to sit on the dashboard itself, which is five of
/// the eight things a player could tap on the main screen spent on pages nobody
/// opens in a hurry. They are behind the Record tile now, and this is the page.
struct RecordLinks: View {
    var body: some View {
        // A list, each with a line saying what is behind it. These were five
        // bordered chips in an adaptive grid, which came out two to a row
        // and one left over, each a different width, with a paragraph below
        // them explaining what the five were.
        VStack(spacing: 0) {
            row("Lineage", "The queens, one after another", systemImage: "crown.fill") {
                LineageView()
            }
            Divider().padding(.leading, 44)
            row("Almanac", "What happened, and when", systemImage: "book.fill") {
                AlmanacView()
            }
            Divider().padding(.leading, 44)
            row("Collection", "Every flower you have photographed", systemImage: "leaf.fill") {
                CollectionView()
            }
            Divider().padding(.leading, 44)
            row("Milestones", "The colony's firsts", systemImage: "rosette") {
                MilestonesView()
            }
            Divider().padding(.leading, 44)
            row("History", "The numbers, charted", systemImage: "chart.xyaxis.line") {
                HistoryView()
            }
        }
        .card()
    }

    private func row<Destination: View>(
        _ title: LocalizedStringKey,
        _ detail: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.honey)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
