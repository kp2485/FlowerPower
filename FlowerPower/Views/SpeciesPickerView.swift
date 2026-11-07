//
//  SpeciesPickerView.swift
//  FlowerPower
//
//  Letting the player say what the flower is.
//
//  There are two reasons this exists, and the second is the pressing one.
//
//  A classifier is sometimes wrong, and a player who can see it is wrong
//  should be able to say so rather than watch their bees work a
//  misidentified patch.
//
//  And a build without the BioCLIP model cannot name much at all: stage one
//  asks "is this a plant?", stage two asks "which one?", and stage two is
//  optional. With nothing to answer it every flower is unidentified and
//  yields 60% of normal, for ever. That is a playable game but a dull one,
//  and it makes the whole catalogue — thirty species with different nectar,
//  different seasons, and the keystone plants that carry a colony through
//  the gaps — invisible.
//
//  So the player can name it. That is a deliberate choice to trust them: this
//  is a game about going outside and looking at flowers, and somebody who has
//  knelt down to photograph a viper's bugloss probably knows what it is.
//
//  The catalogue comes first, because those are the plants the game is about.
//  Below it, when the taxon index is on the phone, is every flowering plant
//  there is: a player who knows their peony is a peony can say so, and the
//  colony will be given a peony — all pollen, no nectar — rather than a
//  generic flower.
//

import SwiftUI
import FlowerPowerCore

struct SpeciesPickerView: View {

    /// Confidence recorded for a name the player chose themselves.
    ///
    /// Not 1.0. Confidence scales the patch's yield, and a person naming a
    /// flower from a phone screen is usually right but not certain — the same
    /// standing a good classifier result gets. Making it perfect would also
    /// make self-identifying strictly better than photographing well, which
    /// is the wrong incentive for this game.
    static let manualConfidence: Double = 0.8

    let onChoose: (FlowerSpecies) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var index: TaxonEmbeddingIndex?

    private var results: [FlowerSpecies] {
        guard !search.isEmpty else { return FlowerCatalogue.all }
        let needle = search.lowercased()
        return FlowerCatalogue.all.filter { species in
            species.commonName.lowercased().contains(needle)
                || (species.scientificName?.lowercased().contains(needle) ?? false)
        }
    }

    /// Everything else the identifier knows that matches, minus what the
    /// catalogue already offered.
    ///
    /// Held rather than computed. As a computed property it scanned 57,000
    /// names on the main thread twice per redraw, and typing lagged; now it
    /// is worked out once a pause in typing, off the main actor.
    @State private var worldResults: [TaxonEmbeddingIndex.Entry] = []

    /// The query `worldResults` answers. Until it matches what is typed, the
    /// wider search is still going, and the list says so: it used to show an
    /// empty sheet for three seconds, which reads as "nothing matches".
    @State private var searchedFor = ""
    private var isSearching: Bool { !search.isEmpty && searchedFor != search }

    @concurrent
    nonisolated private static func search(
        _ index: TaxonEmbeddingIndex,
        for query: String,
        excluding catalogued: Set<Taxon>
    ) async -> [TaxonEmbeddingIndex.Entry] {
        index.search(query, limit: 30).filter { !catalogued.contains($0.taxon) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        ForEach(FlowerCatalogue.all.filter(\.isKeystone), id: \.id) { species in
                            row(species)
                        }
                    } header: {
                        Text("Keystone Flowers")
                    } footer: {
                        Text("These bloom when little else does, and are what carry a colony through the gaps.")
                    }
                }

                if !results.isEmpty {
                    Section(search.isEmpty ? "All Flowers" : "Matches") {
                        ForEach(results, id: \.id) { species in
                            row(species)
                        }
                    }
                }

                if isSearching {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching every flowering plant…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !search.isEmpty, results.isEmpty, worldResults.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                }

                if !worldResults.isEmpty, !isSearching {
                    Section {
                        ForEach(worldResults, id: \.self) { entry in
                            worldRow(entry)
                        }
                    } header: {
                        Text("Every Flowering Plant")
                    } footer: {
                        Text("Plants the catalogue does not describe. Your bees will work one as its family typically forages.")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search flowers")
            .task {
                index = await TaxonIndexStore.shared.index
            }
            .task(id: SearchKey(query: search, hasIndex: index != nil)) {
                guard !search.isEmpty else {
                    worldResults = []
                    searchedFor = ""
                    return
                }
                // Still loading: `isSearching` holds, and this runs again
                // when the index arrives, because it is part of the key.
                guard let index else { return }
                // A pause in typing; a new keystroke cancels this one.
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                let query = search
                let found = await Self.search(index, for: query, excluding: Set(results.map(\.taxon)))
                guard !Task.isCancelled else { return }
                worldResults = found
                searchedFor = query
            }
            .navigationTitle("What Is It?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ species: FlowerSpecies) -> some View {
        Button {
            onChoose(species)
            dismiss()
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(species.commonName)
                        .foregroundStyle(.primary)
                    if let scientific = species.scientificName {
                        Text(scientific)
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                    }
                    Text(Season.allCases.filter(species.bloomSeasons.contains)
                        .map { $0.rawValue.capitalized }
                        .joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if species.isKeystone {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.queen)
                        .imageScale(.small)
                        .accessibilityLabel("keystone")
                }
            }
        }
    }

    private func worldRow(_ entry: TaxonEmbeddingIndex.Entry) -> some View {
        Button {
            let taxon = entry.taxon
            let species = FlowerCatalogue.all.first { $0.taxon == taxon }
                ?? FlowerSpecies.generic(for: taxon, commonName: entry.commonName)
            onChoose(species)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.commonName.isEmpty ? entry.scientificName : entry.commonName.capitalisingFirst)
                    .foregroundStyle(.primary)
                Text(entry.commonName.isEmpty
                     ? "\(entry.rank.displayName) · \(BotanicalFamily(entry.family).commonName)"
                     : "\(entry.scientificName) · \(BotanicalFamily(entry.family).commonName)")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchKey: Equatable {
    let query: String
    let hasIndex: Bool
}

#Preview {
    SpeciesPickerView { _ in }
}
