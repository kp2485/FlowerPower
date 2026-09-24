//
//  GardenView.swift
//  FlowerPower
//
//  Every flower the player has ever found, and the record of what it fed.
//
//  This is the part of the game that outlives the colony. A hive can die; the
//  garden is a year of walks. It is also where sharing lives — a flower you
//  found, with what your bees made of it, sent to somebody.
//
//  Every tile is pressable and every tile is holdable. A long press shows the
//  photograph large with the flower's name and state under it, and the three
//  things there are to do with a flower — send it, say what it is, look it up
//  — without opening anything. None of those actions are new; they are the
//  ones already on the detail sheet and in the capture flow, brought within
//  reach of the grid.
//

import SwiftUI
import Photos
import TipKit
import FlowerPowerCore
import FlowerPowerGame

struct GardenView: View {

    @Environment(GameStore.self) private var store
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.northern.rawValue
    var onPhotograph: () -> Void

    @State private var filter: Filter = .all
    /// What the grid has opened, if anything. One piece of state rather than
    /// four booleans, because several `.sheet` modifiers stacked on one view
    /// is a way of finding out which of them SwiftUI honours.
    @State private var route: Route?
    /// Bumped when a tile is opened, so the grid ticks under a finger the way
    /// the rest of the app does.
    @State private var opens = 0

    /// Where a tile can lead. Every case is a screen that already existed.
    enum Route: Identifiable {
        /// The flower, at length.
        case detail(PatchSummary)
        /// Sending it to somebody — the same sheet the detail's toolbar opens.
        case share(PatchSummary)
        /// Saying what it is, as the capture flow lets the player do.
        case identify(PatchSummary)
        /// The catalogue's page for it.
        case guideEntry(FieldGuideEntry)

        var id: String {
            switch self {
            case .detail(let patch): return "detail-\(patch.id.rawValue)"
            case .share(let patch): return "share-\(patch.id.rawValue)"
            case .identify(let patch): return "identify-\(patch.id.rawValue)"
            case .guideEntry(let entry): return "guide-\(entry.id)"
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case inBloom = "In Bloom"
        case unidentified = "Unidentified"
        case rare = "Rare"

        var id: String { rawValue }
    }

    private var snapshot: ColonySnapshot { store.snapshot }

    private var patches: [PatchSummary] {
        switch filter {
        case .all: return snapshot.patches
        case .inBloom: return snapshot.patches.filter(\.isInBloom)
        case .unidentified: return snapshot.patches.filter { !$0.isIdentified }
        case .rare: return snapshot.patches.filter { $0.rarity != .common }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.patches.isEmpty {
                    // The garden is the player's own flowers and stays that
                    // way — but what it says when it is empty depends on
                    // whether the bees have anything else, and since the
                    // world was drawn they usually do.
                    EmptyGardenView(
                        hasWildForage: !snapshot.wildPatches.isEmpty,
                        onPhotograph: onPhotograph
                    )
                } else {
                    gardenGrid
                }
            }
            .navigationTitle("Garden")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                // The guide to everything, as against the garden of what has
                // been found. It belongs next to the camera button: this is
                // the screen somebody opens before going out.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FieldGuideView()
                    } label: {
                        Label("Field Guide", systemImage: "book.closed")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Photograph", systemImage: "camera.fill", action: onPhotograph)
                }
            }
            .sensoryFeedback(.selection, trigger: opens)
            .sheet(item: $route) { route in
                destination(for: route)
            }
        }
    }

    /// What each route opens.
    ///
    /// A function of its own rather than the switch written into `.sheet`'s
    /// closure: four cases that bind a value, one of them with a trailing
    /// closure and one a stack with a toolbar, is a lot to infer inside a
    /// closure argument, and here the return type is written down. The
    /// guide's page is the one case with a body of its own, for the same
    /// reason.
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .detail(let patch):
            FlowerDetailView(patch: patch)
        case .share(let patch):
            ShareFlowerView(patch: patch)
        case .identify(let patch):
            SpeciesPickerView { species in
                store.attachIdentification(
                    species,
                    confidence: SpeciesPickerView.manualConfidence,
                    to: patch.id
                )
            }
        case .guideEntry(let entry):
            guidePage(for: entry)
        }
    }

    private func guidePage(for entry: FieldGuideEntry) -> some View {
        NavigationStack {
            FieldGuideDetailView(entry: entry, hemisphere: hemisphere)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // `dismiss` here would close the garden, not the
                        // sheet: this is part of the garden's own view.
                        Button("Done") { route = nil }
                    }
                }
        }
    }

    /// Which half of the world the player is in, for the guide's bloom
    /// calendar. The same preference `FieldGuideView` and `CollectionView`
    /// read, under the same key.
    private var hemisphere: Hemisphere { Hemisphere(rawValue: hemisphereRaw) ?? .northern }

    private var gardenGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                TipView(AppTips.garden)
                SeasonalAdviceCard(season: snapshot.season)

                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if patches.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No flowers match this filter.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(patches) { patch in
                            Button {
                                route = .detail(patch)
                                opens += 1
                            } label: {
                                FlowerThumbnail(patch: patch)
                            }
                            .buttonStyle(.pressableTile)
                            .contextMenu {
                                menu(for: patch)
                            } preview: {
                                FlowerPreview(patch: patch)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// What a held tile offers.
    ///
    /// Nothing here is invented: opening it is the tap, sharing is the button
    /// in `FlowerDetailView`'s toolbar, naming it is `SpeciesPickerView` as
    /// the capture flow uses it, and the guide page is the one
    /// `FieldGuideView` pushes. The menu is a shortcut past a sheet, not a
    /// second set of features.
    @ViewBuilder
    private func menu(for patch: PatchSummary) -> some View {
        Button("Open", systemImage: "info.circle") {
            route = .detail(patch)
        }

        Button("Send to a Friend", systemImage: "square.and.arrow.up") {
            route = .share(patch)
        }

        // Offered whatever the placement, because a plant put to a family is
        // not identified either and the player may well know the species.
        // The title is bound to a `String` first: a ternary of two string
        // literals passed straight in has two initialisers to choose from.
        let naming: String = patch.isIdentified ? "Name It Again" : "Name It Yourself"
        Button(naming, systemImage: "text.magnifyingglass") {
            route = .identify(patch)
        }

        if let entry = guideEntry(for: patch) {
            Button("Field Guide Entry", systemImage: "book.closed") {
                route = .guideEntry(entry)
            }
        }
    }

    /// The guide's page for this flower, when the plant was placed finely
    /// enough for the catalogue to have one. A patch known only to a family
    /// has no species page to open, and offering one would be a lie.
    private func guideEntry(for patch: PatchSummary) -> FieldGuideEntry? {
        guard let taxon = patch.taxon, taxon.rank == .species,
              let species = FlowerCatalogue.all.first(where: { $0.taxon == taxon })
        else { return nil }
        return FieldGuide(patches: snapshot.patches).entry(id: species.id)
    }
}

// MARK: - Seasonal advice

/// Tells the player what is worth looking for right now. This is the single
/// most useful thing the app can say to someone about to go outside.
private struct SeasonalAdviceCard: View {

    let season: Season

    private var keystones: [FlowerSpecies] {
        Array(FlowerCatalogue.keystones(for: season).prefix(3))
    }

    private var best: [FlowerSpecies] {
        Array(FlowerCatalogue.inBloom(during: season).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Worth finding in \(season.displayName.lowercased())", systemImage: Theme.symbol(for: season))
                .font(.subheadline.weight(.semibold))

            if best.isEmpty {
                Text("Almost nothing flowers now. Your bees are living on what they stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(best.map(\.commonName).formatted(.list(type: .and)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !keystones.isEmpty {
                Label(
                    "\(keystones.map(\.commonName).formatted(.list(type: .and))) — these bloom when little else does, and are worth far more than their yield suggests.",
                    systemImage: "star.fill"
                )
                .font(.caption2)
                .foregroundStyle(Theme.honey)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Thumbnail

private struct FlowerThumbnail: View {

    let patch: PatchSummary

    var body: some View {
        VStack(spacing: 0) {
            PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if patch.rarity != .common {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !patch.isInBloom {
                        Text("Out of season")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(4)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(patch.speciesName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(patch.isIdentified ? .primary : .secondary)

                ProgressView(value: patch.remainingFraction)
                    .tint(Theme.nectar)
                    .scaleEffect(y: 0.6, anchor: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenName)
        .accessibilityValue("\(Int(patch.remainingFraction * 100)) percent forage left")
    }

    /// The star and the "out of season" pill are the two things a tile says
    /// with a badge rather than a word, so the label says them instead.
    private var spokenName: String {
        var parts = [patch.speciesName]
        if patch.rarity != .common { parts.append(patch.rarity.displayName.lowercased()) }
        if !patch.isInBloom { parts.append("out of season") }
        return parts.joined(separator: ", ")
    }
}

/// What a held tile lifts off the grid: the photograph, large, and the three
/// things about it that are true today.
///
/// Deliberately not the detail sheet in miniature. A context-menu preview is
/// read in the second before a finger moves to the menu, so it carries the
/// picture and a line, and everything else waits for the tap.
private struct FlowerPreview: View {

    let patch: PatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 260, height: 260)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(patch.speciesName)
                    .font(.headline)
                    .lineLimit(2)

                if let scientific = patch.scientificName {
                    Text(scientific)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }

                Text(state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(patch.speciesName)
        // The middle dot is a typographic join, not a word.
        .accessibilityValue(parts.joined(separator: ", "))
    }

    /// Where this flower stands today: in bloom or not, how much is left, and
    /// who is on it.
    private var state: String { parts.joined(separator: " · ") }

    private var parts: [String] {
        var parts: [String] = [patch.isInBloom ? "In bloom" : "Out of season"]
        parts.append("\(Int(patch.remainingFraction * 100))% forage left")
        if patch.foragersWorkingIt > 0 {
            parts.append("\(patch.foragersWorkingIt) bees on it")
        }
        if !patch.isIdentified { parts.append("not yet named") }
        return parts
    }
}

/// Loads a thumbnail for a patch.
///
/// Two sources behind one view. A flower the player photographed is a
/// `PHAsset` in their library; one somebody sent them never entered it, on
/// purpose, and lives in the app's own container instead. The identifier says
/// which — see `SharedImageStore`.
struct PhotoThumbnail: View {

    let localIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.wax.opacity(0.5))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
            }
        }
        .task(id: localIdentifier) { @MainActor in
            if FlowerShare.isSharedIdentifier(localIdentifier) {
                image = SharedImageStore.image(forLocalIdentifier: localIdentifier)
            } else {
                image = await PhotoLibrary.thumbnail(
                    for: localIdentifier,
                    size: CGSize(width: 400, height: 400)
                )
            }
        }
    }
}

// MARK: - Detail and sharing

/// One flower, at length. Not private: the World map opens the same sheet for
/// the same patch, and a flower tapped on the map and a flower tapped in the
/// garden should not be two different descriptions of it.
///
/// At length, but not all at once. This screen used to open with three full
/// cards under the photograph — the patch's state, the species' yield, and
/// the trait diagram — which is four scrolls of text for a question that is
/// usually "is there anything left on it". So the figures worth glancing at
/// sit in a row under the name, and the two cards of prose behind them open
/// on a tap. The diagram is left alone: it is a picture rather than a list,
/// and a picture folded shut says nothing at all.
struct FlowerDetailView: View {

    let patch: PatchSummary
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    /// The catalogue entry when the plant was placed to a species, and the
    /// family's or genus's typical forage when it was placed less precisely —
    /// which is still a real description, and still worth explaining.
    private var species: FlowerSpecies? {
        guard let taxon = patch.taxon else { return nil }
        return FlowerCatalogue.all.first { $0.taxon == taxon }
            ?? FlowerSpecies.generic(for: taxon)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement()
                        .accessibilityLabel("Your photograph of \(patch.speciesName)")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(patch.speciesName)
                            .font(.title2.weight(.semibold))

                        if let scientific = species?.scientificName {
                            Text(scientific)
                                .font(.subheadline.italic())
                                .foregroundStyle(.secondary)
                        }

                        Text(patch.discoveredAt.formatted(date: .long, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if patch.isShared {
                            Label(
                                patch.sharedBy.map { "Sent by \($0)" } ?? "Sent by a friend",
                                systemImage: "gift.fill"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.queen)
                            .padding(.top, 2)
                        }
                    }

                    GlanceRow(patch: patch)

                    PatchStateCard(patch: patch)

                    if let species {
                        FlowerFactsCard(species: species, patch: patch)
                        FloralTraitsView(species: species)
                    }

                    if !patch.isIdentified {
                        Text("Your bees still forage this one, at a reduced yield. A clearer, closer photo may let it be identified.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    // Sends the flower itself rather than a picture of it.
                    // This used to be a plain `ShareLink` on the image, which
                    // sent a photograph that was pleasant to receive and fed
                    // nobody's bees.
                    Button {
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareFlowerView(patch: patch)
            }
        }
    }
}

/// The three figures somebody opened this sheet for, on one line.
///
/// A player tapping a thumbnail almost always wants one of: is it flowering,
/// is there anything left, is anyone on it. Answering that above the fold is
/// what lets the cards underneath stay shut.
private struct GlanceRow: View {

    let patch: PatchSummary

    var body: some View {
        HStack(spacing: 10) {
            Figure(
                value: "\(Int(patch.remainingFraction * 100))%",
                label: "Forage left",
                tint: Theme.nectar,
                symbolName: "drop.fill"
            )
            Figure(
                value: "\(patch.foragersWorkingIt)",
                label: "Bees on it",
                tint: Theme.worker,
                symbolName: "circle.hexagongrid.fill"
            )
            Figure(
                value: patch.isInBloom ? "Yes" : "No",
                label: "In bloom",
                tint: patch.isInBloom ? Theme.healthy : Theme.caution,
                symbolName: patch.isInBloom ? "sun.max.fill" : "calendar.badge.exclamationmark"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private struct Figure: View {

        let value: String
        let label: String
        let tint: Color
        let symbolName: String

        var body: some View {
            VStack(spacing: 4) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .imageScale(.small)
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}

/// A card that stays shut until it is asked for.
///
/// One line of summary on the closed row, so that folding a card away never
/// hides the answer — only the working. The chevron and the whole row are the
/// control, which is what `DisclosureGroup` gives for free.
private struct ExpandableCard<Content: View>: View {

    let title: String
    let symbolName: String
    /// The gist, read without opening it.
    let summary: String
    let content: Content

    /// Written out rather than left to the memberwise one, so the trailing
    /// closure is a view builder without relying on the synthesised
    /// initialiser to carry the attribute across.
    init(
        title: String,
        symbolName: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.summary = summary
        self.content = content()
    }

    /// Shut to begin with, every time. A card that opens by default is the
    /// thing this type exists to stop.
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbolName)
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "Collapses the details" : "Expands the details")
        }
        .tint(Theme.honey)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sensoryFeedback(.selection, trigger: isExpanded)
    }
}

/// What this one patch is doing today, as against what the species is like in
/// general: how much of it is left, how many bees are on it, and whether it is
/// flowering at all. These are facts about the flower in the photograph rather
/// than about its kind, so they sit above the reference material.
private struct PatchStateCard: View {

    let patch: PatchSummary

    var body: some View {
        ExpandableCard(
            title: "Right now",
            symbolName: "clock.fill",
            summary: summary
        ) {
            details
        }
    }

    /// The closed row's line: where it stands and how far off it is.
    private var summary: String {
        var parts: [String] = ["\(Int(patch.remainingFraction * 100))% of the stand left"]
        if let cell = patch.cell {
            let metres = Int(Double(HexCoordinate.origin.distance(to: cell)) * HexCoordinate.cellMetres)
            parts.append("\(metres) m from the nest")
        }
        if !patch.isInBloom { parts.append("not in bloom") }
        return parts.joined(separator: ", ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            MeterView(
                label: "Forage remaining",
                value: patch.remainingFraction,
                caption: "\(Int(patch.remainingFraction * 100))%",
                tint: Theme.nectar,
                symbolName: "drop.fill"
            )

            LabeledContent("Bees working it", value: "\(patch.foragersWorkingIt)")
                .font(.subheadline)

            // Where it stands. Distance was taken off this screen the day
            // location came out of the app, and rightly: every patch sat at
            // the same nominal 800 m, so the number said nothing. It says
            // something again — a flower in the first ring is worked at a
            // distance efficiency of 0.89 against 0.67, and the player can
            // see which of their flowers are the close ones.
            if let cell = patch.cell {
                let ring = HexCoordinate.origin.distance(to: cell)
                let metres = Int(Double(ring) * HexCoordinate.cellMetres)

                Label(
                    "In the garden · \(metres) m from the nest, ring \(ring)",
                    systemImage: "mappin.and.ellipse"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // The middle dot is a typographic join, not a word.
                .accessibilityLabel("In the garden, \(metres) metres from the nest, ring \(ring)")
            }

            if !patch.isInBloom {
                Label("Not in bloom this season", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowerFactsCard: View {

    let species: FlowerSpecies
    let patch: PatchSummary

    var body: some View {
        ExpandableCard(
            title: "What your bees make of it",
            symbolName: "drop.fill",
            summary: summary
        ) {
            details
        }
    }

    /// The closed row: the yield in a phrase, when it flowers, and the one
    /// word that changes how the plant is worth having.
    private var summary: String {
        var parts: [String] = [
            species.nectarRichness == 0 ? "No nectar, pollen only" : "Nectar and pollen"
        ]
        parts.append(species.bloomSeasons
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .formatted(.list(type: .and)))
        if species.isKeystone { parts.append("keystone") }
        return parts.joined(separator: " · ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            MeterView(
                label: "Nectar",
                value: min(1, species.nectarRichness / 2.5),
                caption: species.nectarRichness == 0 ? "None" : nil,
                tint: Theme.nectar,
                symbolName: "drop.fill"
            )
            MeterView(
                label: "Pollen",
                value: min(1, species.pollenRichness / 2.0),
                tint: Theme.pollen,
                symbolName: "circle.grid.3x3.fill"
            )

            LabeledContent("Blooms") {
                Text(species.bloomSeasons
                    .sorted { $0.rawValue < $1.rawValue }
                    .map(\.displayName)
                    .formatted(.list(type: .and)))
            }
            .font(.subheadline)

            LabeledContent("Rarity", value: patch.rarity.displayName)
                .font(.subheadline)

            if species.isKeystone {
                Label(
                    "A keystone plant — it flowers when the colony has few other options, which makes it worth more than its yield alone.",
                    systemImage: "star.fill"
                )
                .font(.caption)
                .foregroundStyle(Theme.honey)
                .fixedSize(horizontal: false, vertical: true)
            }

            if species.nectarRichness == 0 {
                Label(
                    "This one offers no nectar at all — only pollen. Your bees take it for the brood, not for honey.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty state

private struct EmptyGardenView: View {

    /// Whether there is anything standing wild within flying range. A colony
    /// with a heath at the end of the lane is not being starved by an empty
    /// garden, and telling it so would be a lie the map contradicts.
    var hasWildForage = false
    var onPhotograph: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Flowers Yet", systemImage: "camera.macro")
        } description: {
            Text(hasWildForage
                 ? "Your bees are living on what they can find in the country around them. A flower you photograph is far richer than anything wild — it is the difference between getting through the year and getting through the winter."
                 : "Your bees can only eat what you find for them. Photograph a flower to start.")
        } actions: {
            Button("Photograph a Flower", action: onPhotograph)
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
        }
    }
}

#Preview {
    GardenView(onPhotograph: {})
        .environment(GameStore.preview())
}
