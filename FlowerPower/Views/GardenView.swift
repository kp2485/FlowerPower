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

import SwiftUI
import Photos
import FlowerPowerCore
import FlowerPowerGame

struct GardenView: View {

    @Environment(GameStore.self) private var store
    var onPhotograph: () -> Void

    @State private var filter: Filter = .all
    @State private var selected: PatchSummary?

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
                    EmptyGardenView(onPhotograph: onPhotograph)
                } else {
                    gardenGrid
                }
            }
            .navigationTitle("Garden")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Photograph", systemImage: "camera.fill", action: onPhotograph)
                }
            }
            .sheet(item: $selected) { patch in
                FlowerDetailView(patch: patch)
            }
        }
    }

    private var gardenGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                                selected = patch
                            } label: {
                                FlowerThumbnail(patch: patch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !patch.isInBloom {
                        Text("Out of season")
                            .font(.system(size: 9, weight: .medium))
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
        .accessibilityLabel("\(patch.speciesName), \(Int(patch.remainingFraction * 100)) percent forage left")
    }
}

/// Loads a thumbnail from the photo library by local identifier.
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
                    }
            }
        }
        .task(id: localIdentifier) { @MainActor in
            image = await PhotoLibrary.thumbnail(for: localIdentifier, size: CGSize(width: 400, height: 400))
        }
    }
}

// MARK: - Detail and sharing

private struct FlowerDetailView: View {

    let patch: PatchSummary
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: UIImage?

    private var species: FlowerSpecies? {
        FlowerCatalogue.all.first { $0.commonName == patch.speciesName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

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
                    }

                    if let species {
                        FlowerFactsCard(species: species, patch: patch)
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
                    if let fullImage {
                        // Sharing is user-initiated and goes through the system
                        // share sheet, so the player chooses the recipient and
                        // nothing leaves the device without them saying so.
                        ShareLink(
                            item: Image(uiImage: fullImage),
                            preview: SharePreview(shareCaption, image: Image(uiImage: fullImage))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { @MainActor in
                fullImage = await PhotoLibrary.thumbnail(
                    for: patch.photoLocalIdentifier,
                    size: CGSize(width: 1600, height: 1600)
                )
            }
        }
    }

    private var shareCaption: String {
        patch.isIdentified
            ? "\(patch.speciesName) — found and fed to my bees 🐝"
            : "Found this one for my bees 🐝"
    }
}

private struct FlowerFactsCard: View {

    let species: FlowerSpecies
    let patch: PatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("What your bees make of it", systemImage: "drop.fill")

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

            LabeledContent("Distance") {
                Text(Measurement(value: patch.distanceMetres, unit: UnitLength.meters),
                     format: .measurement(width: .abbreviated))
            }
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
        .card()
    }
}

// MARK: - Empty state

private struct EmptyGardenView: View {

    var onPhotograph: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Flowers Yet", systemImage: "camera.macro")
        } description: {
            Text("Your bees can only eat what you find for them. Photograph a flower to start.")
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
