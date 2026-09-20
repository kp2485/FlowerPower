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
//  So the screen is a grid of tiles: a symbol, one number, a caption and a
//  colour apiece, and each one a way in to the full-size section it replaced —
//  which still exists, unchanged, one tap away in `ColonyDetailViews.swift`.
//  What a tile says and how worried it looks is `DashboardSummary` in the
//  package, tested there without a Mac; this file only draws it.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onPhotograph: () -> Void
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.northern.rawValue

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
        DashboardSummary(snapshot: snapshot, history: store.history)
    }

    /// Two columns on a phone, more on anything wider, and one at the
    /// accessibility text sizes where 150 points is a single word.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    StatusHeader(snapshot: snapshot)

                    // Decisions first, and first by a clear margin: everything
                    // below this is a thing to know, and these are the only
                    // things to do.
                    DecisionRows(snapshot: snapshot, open: $openDecision)

                    if !summary.attention.isEmpty {
                        AttentionRow(
                            attention: summary.attention,
                            alerts: snapshot.alerts,
                            isExpanded: $showingAlerts
                        )
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(summary.tiles) { tile in
                            NavigationLink(value: tile.kind) {
                                ColonyTile(tile: tile)
                            }
                            .buttonStyle(TilePressStyle(reduceMotion: reduceMotion))
                            .contextMenu {
                                Button {
                                    path.append(tile.kind)
                                } label: {
                                    Label("Open \(tile.title)", systemImage: "chevron.right")
                                }
                            } preview: {
                                TilePreview(tile: tile, snapshot: snapshot)
                            }
                        }
                    }

                    // The gentlest possible way of getting someone outside —
                    // and emphatically not hidden in winter, which is where
                    // this used to be switched off. Two plants flower in
                    // winter, both of them keystones, and they are the only
                    // things that do. That is exactly when it is worth being
                    // told.
                    BloomPromptCard(prompt: BloomPrompt(
                        hemisphere: Hemisphere(rawValue: hemisphereRaw) ?? .northern,
                        patches: snapshot.patches,
                        terrain: snapshot.terrain,
                        wildPatches: snapshot.wildPatches
                    ))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Colony")
            .navigationDestination(for: DashboardSummary.Tile.Kind.self) { kind in
                ColonyDetailView(kind: kind, onPhotograph: onPhotograph)
            }
            .sensoryFeedback(.selection, trigger: path.count)
            .sheet(item: $openDecision) { kind in
                DecisionSheet(kind: kind, snapshot: snapshot) { openDecision = nil }
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

// MARK: - A tile

/// One box in the grid: a symbol, a number, what the number is, and a colour
/// that says how worried to be about it.
///
/// Everything here arrives already decided. The view picks no thresholds and
/// formats no numbers — if a tile is amber it is because `DashboardSummary`
/// said so, and that judgement has a test with a name.
struct ColonyTile: View {

    let tile: DashboardSummary.Tile

    private var tint: Color { Theme.colour(for: tile.severity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: tile.symbolName)
                    .foregroundStyle(tint)
                    .imageScale(.medium)
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                if let trend = tile.trend {
                    Image(systemName: trend.symbolName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(tile.headline)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(tile.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(tile.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let gauge = tile.gauge {
                Gauge(value: min(1, max(0, gauge)), in: 0...1) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        // One element with a label and a value, so VoiceOver says "Stores, 82
        // percent of what winter needs" rather than reading four fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.spoken)
        .accessibilityHint("Opens \(tile.title.lowercased())")
    }
}

/// A tile that knows it has been pressed.
///
/// The whole point of the rebuild is that the screen feels like something you
/// touch, and a box that does not move under a finger does not. The scale is
/// small on purpose — three per cent, which is felt rather than watched — and
/// it is off entirely for anyone who has asked for less motion, who gets the
/// dimming alone.
struct TilePressStyle: ButtonStyle {

    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
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
                .foregroundStyle(Theme.colour(for: tile.severity))

            switch tile.kind {
            case .stores:
                let ordered = ResourceKind.allCases
                    .filter { (snapshot.stores.resources[$0] ?? 0) > 0.5 }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(ordered, id: \.self) { kind in
                        ResourceTile(kind: kind, amount: snapshot.stores.resources[kind] ?? 0)
                    }
                }
            case .population:
                HStack(spacing: 0) {
                    CountPill(value: snapshot.population.adults, label: "Adults")
                    CountPill(value: snapshot.population.brood, label: "Brood")
                    CountPill(value: snapshot.population.drones, label: "Drones")
                }
                BroodBar(population: snapshot.population)
            case .nest:
                HStack(spacing: 20) {
                    ReadingView(
                        symbol: "thermometer.medium",
                        value: String(format: "%.1f°C", snapshot.nest.temperatureCelsius),
                        label: "Brood nest",
                        tint: abs(snapshot.nest.temperatureCelsius - 35) < 2
                            ? Theme.healthy : Theme.caution
                    )
                    ReadingView(
                        symbol: "humidity.fill",
                        value: String(format: "%.0f%%", snapshot.nest.humidity * 100),
                        label: "Humidity",
                        tint: Theme.colour(for: .water)
                    )
                    ReadingView(
                        symbol: "hexagon.fill",
                        value: "\(snapshot.nest.freeCells)",
                        label: "Free cells",
                        tint: Theme.comb
                    )
                }
            default:
                Text(tile.spoken)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
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

    var body: some View {
        VStack(spacing: 8) {
            if let threat = snapshot.activeThreat {
                DecisionRow(
                    kind: .threat,
                    title: "\(threat.predator.displayName) at the nest",
                    detail: remaining(threat),
                    symbolName: Theme.symbol(for: threat.predator),
                    tint: Theme.alarm,
                    open: $open
                )
            }
            if let swarm = snapshot.pendingSwarm {
                DecisionRow(
                    kind: .swarm,
                    title: swarm.discouraged
                        ? "Making room — it may still go"
                        : "Preparing to swarm",
                    detail: days(swarm.daysRemaining(on: snapshot.day)),
                    symbolName: "arrow.triangle.branch",
                    tint: Theme.caution,
                    open: $open
                )
            }
            if snapshot.departedSwarm != nil {
                DecisionRow(
                    kind: .departed,
                    title: "A swarm has left",
                    detail: "stay, follow, or give it away",
                    symbolName: "bird.fill",
                    tint: Theme.queen,
                    open: $open
                )
            }
            if snapshot.entranceDecisionOpen {
                DecisionRow(
                    kind: .entrance,
                    title: "Autumn: the entrance",
                    detail: "seal it or keep it open",
                    symbolName: "door.left.hand.closed",
                    tint: Theme.propolis,
                    open: $open
                )
            }
            // Short for winter, with honey of theirs in the bank. The engine
            // decides when this is open — the same judgement the winter-stores
            // alert is raised from — so this asks rather than working it out
            // again.
            if snapshot.feedDecisionOpen {
                DecisionRow(
                    kind: .feed,
                    title: "They are short for winter",
                    detail: String(format: "%.0f units short", snapshot.storesShortfall),
                    symbolName: "takeoutbag.and.cup.and.straw.fill",
                    tint: Theme.caution,
                    open: $open
                )
            }
            // Last of them, and the only one that arrives while things are
            // going well: a flow is when a tenth of the force is affordable.
            // Kept on screen while the party is away so that the answer is
            // reported where the question was asked.
            if snapshot.terrain != nil, snapshot.scoutDecisionOpen || snapshot.scoutsOut {
                DecisionRow(
                    kind: .scout,
                    title: snapshot.scoutsOut ? "The scouts are out" : "Ground they have not seen",
                    detail: snapshot.scoutsOut
                        ? back(in: snapshot.scoutsDaysRemaining)
                        : "a tenth of the foragers, for 3 days",
                    symbolName: "map.fill",
                    tint: Theme.wild,
                    open: $open
                )
            }
        }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .buttonStyle(TilePressStyle(reduceMotion: reduceMotion))
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

    @ViewBuilder
    private func card(for kind: DecisionKind) -> some View {
        switch kind {
        case .threat:
            if let threat = snapshot.activeThreat {
                ThreatDecisionCard(threat: threat, snapshot: snapshot)
            } else {
                Answered()
            }
        case .swarm:
            if let swarm = snapshot.pendingSwarm {
                SwarmDecisionCard(swarm: swarm, snapshot: snapshot)
            } else {
                Answered()
            }
        case .departed:
            if let departed = snapshot.departedSwarm {
                DepartedSwarmCard(swarm: departed)
            } else {
                Answered()
            }
        case .entrance:
            if snapshot.entranceDecisionOpen {
                EntranceDecisionCard(snapshot: snapshot)
            } else {
                Answered()
            }
        case .feed:
            if snapshot.feedDecisionOpen {
                FeedDecisionCard(snapshot: snapshot)
            } else {
                Answered()
            }
        case .scout:
            if let terrain = snapshot.terrain {
                ScoutDecisionCard(snapshot: snapshot, terrain: terrain)
            } else {
                Answered()
            }
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

/// The one thing at the top of the screen that is not a tile.
///
/// Tighter than it was: the headline has come down from `.title3` to `.callout`
/// and the season, the weather, whether the bees are out and the day have been
/// folded into a single line of chips under it. Nothing has been dropped — the
/// header is the sentence the watch shows and the notification writes, and it
/// is the only part of the screen that says what the colony is *doing* rather
/// than what it has.
private struct StatusHeader: View {

    let snapshot: ColonySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.status.displayName, systemImage: snapshot.status.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.colour(for: snapshot.status))
                    .minimumScaleFactor(0.7)

                Spacer()

                Label(snapshot.season.displayName, systemImage: Theme.symbol(for: snapshot.season))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
            }

            Text(snapshot.headline)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                WeatherChip(weather: snapshot.weather)

                Label(
                    snapshot.isForaging ? "Foraging" : "In the nest",
                    systemImage: snapshot.isForaging ? "figure.walk.motion" : "house.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)

                Spacer()

                Text("Day \(snapshot.day)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct WeatherChip: View {

    let weather: Weather

    var body: some View {
        Label {
            Text("\(Int(weather.temperatureCelsius))°")
                .monospacedDigit()
        } icon: {
            Image(systemName: Theme.symbol(for: weather.sky))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "\(weather.sky.displayName), \(Int(weather.temperatureCelsius)) degrees"
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

    private var tint: Color { Theme.colour(for: attention.severity) }

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
                        .foregroundStyle(.tertiary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Stores", systemImage: "archivebox.fill")

            // Winter readiness is the number that decides whether the colony
            // sees spring, so it leads from midsummer onward.
            if season == .summer || season == .autumn || season == .winter {
                MeterView(
                    label: "Winter Stores",
                    value: stores.winterReadiness,
                    caption: "\(Int(stores.edibleEnergy)) / \(Int(stores.winterRequirement))",
                    tint: stores.isWinterReady ? Theme.healthy : Theme.caution,
                    symbolName: "snowflake"
                )
            }

            if banked >= 1 {
                Label(
                    "\(Int(banked.rounded())) units taken and still yours to give back",
                    systemImage: "arrow.uturn.backward.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            let ordered = ResourceKind.allCases.filter { (stores.resources[$0] ?? 0) > 0.5 }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                spacing: 12
            ) {
                ForEach(ordered, id: \.self) { kind in
                    ResourceTile(kind: kind, amount: stores.resources[kind] ?? 0)
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: Theme.symbol(for: kind))
                .foregroundStyle(Theme.colour(for: kind))
                .imageScale(.large)
                .accessibilityHidden(true)

            Text(amount, format: .number.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.displayName): \(Int(amount))")
    }
}

// MARK: - Population

struct PopulationSection: View {

    let population: PopulationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Population", systemImage: "person.3.fill")

            HStack(spacing: 0) {
                CountPill(value: population.total, label: "Total")
                CountPill(value: population.adults, label: "Adults")
                CountPill(value: population.brood, label: "Brood")
                CountPill(value: population.drones, label: "Drones")
            }

            BroodBar(population: population)

            if population.winterBees > 0 {
                Label(
                    "\(population.winterBees) winter bees — long-lived, and what carries the colony to spring",
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

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
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

/// Eggs, larvae and pupae as proportions — the shape of the brood nest tells an
/// experienced eye more than the total does.
private struct BroodBar: View {

    let population: PopulationSummary

    private var segments: [(stage: DevelopmentStage, count: Int)] {
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
                            .frame(
                                width: max(2, geometry.size.width
                                          * Double(segment.count) / Double(total) - 2)
                            )
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                ForEach(segments, id: \.stage) { segment in
                    Label("\(segment.count)", systemImage: "circle.fill")
                        .labelStyle(LegendLabelStyle(colour: Theme.colour(for: segment.stage)))
                        .font(.caption2)
                    Text(segment.stage.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Brood: \(population.eggs) eggs, \(population.larvae) larvae, \(population.pupae) pupae"
        )
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
                if queen.state != .absent {
                    Text("\(queen.ageDays) days old")
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
                    caption: "\(queen.patrilines) patrilines",
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
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if queen.daysQueenless > 0 {
                Label("Queenless for \(queen.daysQueenless) days", systemImage: "clock.badge.exclamationmark")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Nest", systemImage: "house.fill")

            HStack {
                Text(nest.siteType.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(nest.builtCells) / \(nest.capacity) cells")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            MeterView(
                label: "Comb Occupancy",
                value: nest.combOccupancy,
                caption: "\(nest.freeCells) free",
                tint: nest.combOccupancy > 0.9 ? Theme.caution : Theme.comb,
                symbolName: "hexagon.fill"
            )

            HStack(spacing: 20) {
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

            if !nest.queenCells.isEmpty {
                let names = Set(nest.queenCells.map(\.displayName)).sorted().joined(separator: ", ")
                Label("\(nest.queenCells.count) queen cells — \(names)", systemImage: "crown")
                    .font(.caption)
                    .foregroundStyle(Theme.queen)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The room question, before it becomes the swarm question. Only
            // shown once the comb has actually filled the cavity — offering
            // space to a colony with empty frames still in it would be noise.
            if nest.builtCells >= nest.capacity {
                RoomRow(nest: nest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// What can be done about a nest that has filled its cavity.
private struct RoomRow: View {

    let nest: NestSummary
    @Environment(GameStore.self) private var store

    /// Counts the times the player has opened the nest up, purely so the
    /// haptic has something to fire on. A trigger value rather than a plain
    /// flag, so it also fires the second time.
    @State private var combAdded = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if nest.siteCanBeExtended {
                Text("The comb has filled the cavity. A \(nest.siteType.displayName.lowercased()) has room for about \(nest.combExtensionRemaining) more cells — give it to them and they will keep building; leave it and they will divide instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    store.addComb()
                    combAdded += 1
                } label: {
                    Label("Open the Nest Up", systemImage: "plus.rectangle.on.rectangle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.honey)
                .sensoryFeedback(.impact(weight: .medium), trigger: combAdded)
            } else {
                Label(
                    "The cavity is full and there is no more of it. A \(nest.siteType.displayName.lowercased()) gives what it gives.",
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
                    caption: String(format: "%.0f%%", level * 100),
                    tint: level > 0.5 ? Theme.alarm : Theme.caution,
                    symbolName: "microbe.fill"
                )
            }

            if health.infections[.varroa] != nil {
                Text("Varroa breeds in sealed brood and carries deformed wing virus. Hygienic bees uncap infested cells and remove them.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
        // A grid rather than a row: there are more of these than fit across a
        // phone now, and a bordered button squeezed to three characters is
        // worse than a second line of them.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            NavigationLink { LineageView() } label: {
                Label("Lineage", systemImage: "crown.fill")
            }
            NavigationLink { AlmanacView() } label: {
                Label("Almanac", systemImage: "book.fill")
            }
            NavigationLink { CollectionView() } label: {
                Label("Collection", systemImage: "leaf.fill")
            }
            NavigationLink { MilestonesView() } label: {
                Label("Milestones", systemImage: "rosette")
            }
            NavigationLink { HistoryView() } label: {
                Label("History", systemImage: "chart.xyaxis.line")
            }
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .tint(Theme.honey)
        .frame(maxWidth: .infinity)
    }
}
