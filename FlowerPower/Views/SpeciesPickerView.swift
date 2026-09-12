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
//  And until a model is trained and bundled, the classifier cannot name
//  anything at all: stage one asks "is this a plant?", stage two asks "which
//  one?", and stage two is optional. With no model every flower is
//  unidentified and yields 60% of normal, for ever. That is a playable game
//  but a dull one, and it makes the whole catalogue — thirty species with
//  different nectar, different seasons, and the keystone plants that carry a
//  colony through the gaps — invisible.
//
//  So the player can name it. That is a deliberate choice to trust them: this
//  is a game about going outside and looking at flowers, and somebody who has
//  knelt down to photograph a viper's bugloss probably knows what it is.
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

    private var results: [FlowerSpecies] {
        guard !search.isEmpty else { return FlowerCatalogue.all }
        let needle = search.lowercased()
        return FlowerCatalogue.all.filter { species in
            species.commonName.lowercased().contains(needle)
                || (species.scientificName?.lowercased().contains(needle) ?? false)
        }
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

                Section(search.isEmpty ? "All Flowers" : "Matches") {
                    ForEach(results, id: \.id) { species in
                        row(species)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search flowers")
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
                    Text(species.bloomSeasons
                        .sorted { $0.rawValue < $1.rawValue }
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
}

#Preview {
    SpeciesPickerView { _ in }
}
