//
//  CollectionView.swift
//  FlowerPower
//
//  The garden as a shelf with spaces on it.
//
//  Families seen against families there are, the bloom calendar with its
//  gaps, and what is out this month that the garden has none of. The gaps are
//  the whole point: not a task, just a space that a walk would fill.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct CollectionView: View {

    @Environment(GameStore.self) private var store
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.northern.rawValue

    private var collection: BotanyCollection { BotanyCollection(patches: store.snapshot.patches) }
    private var hemisphere: Hemisphere { Hemisphere(rawValue: hemisphereRaw) ?? .northern }
    private var prompt: BloomPrompt {
        BloomPrompt(hemisphere: hemisphere, patches: store.snapshot.patches)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Families", value: "\(collection.familiesSeen) of \(collection.familiesTotal)")
                LabeledContent("Species", value: "\(collection.speciesCollected.count) of \(collection.speciesTotal)")
                calendar
            }

            Section {
                BloomPromptCard(prompt: prompt)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Out now, \(prompt.season.rawValue)")
            } footer: {
                Picker("Hemisphere", selection: $hemisphereRaw) {
                    Text("Northern").tag(Hemisphere.northern.rawValue)
                    Text("Southern").tag(Hemisphere.southern.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)
            }

            Section("Families in the garden") {
                ForEach(collection.families) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.family.commonName).font(.headline)
                            Spacer()
                            Text(entry.family.scientificName)
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.family.forageNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(entry))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }

            if !collection.missingFamilies.isEmpty {
                Section("Not yet found") {
                    ForEach(collection.missingFamilies, id: \.self) { family in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(family.commonName).font(.subheadline)
                            Text(family.forageNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            // The sections above are the spaces on the shelf. This is what
            // goes in them: the collection knows what is missing, and only
            // the guide says what to look for.
            Section {
                NavigationLink {
                    FieldGuideView()
                } label: {
                    Label("See what you are missing", systemImage: "book.closed")
                }
            } footer: {
                Text("The field guide lists every plant the game knows, whether or not you have found it — what to look for, when it flowers, and whether your bees can reach the nectar.")
            }
        }
        .navigationTitle("Collection")
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bloom calendar")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                ForEach(Season.allCases, id: \.self) { season in
                    let covered = collection.seasonsCovered.contains(season)
                    Label(season.rawValue.capitalized, systemImage: Theme.symbol(for: season))
                        .font(.caption)
                        .minimumScaleFactor(0.6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(covered ? Theme.honey.opacity(0.25) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(covered ? Theme.honey : .secondary.opacity(0.4)))
                        // Filled or outlined is the whole message of this row,
                        // and it is carried by nothing but the colour.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(season.rawValue.capitalized)
                        .accessibilityValue(covered
                                            ? "something in the garden flowers"
                                            : "nothing in the garden flowers")
                }
            }
            if !collection.seasonsMissing.isEmpty {
                Text("Nothing in the garden flowers in \(collection.seasonsMissing.map { $0.rawValue }.spokenList). The colony has no forage then.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(_ entry: BotanyCollection.FamilyEntry) -> String {
        var parts = ["\(entry.patchCount) photograph\(entry.patchCount == 1 ? "" : "s")"]
        if !entry.genera.isEmpty {
            parts.append("\(entry.genera.count) gen\(entry.genera.count == 1 ? "us" : "era")")
        }
        if !entry.speciesIDs.isEmpty {
            parts.append("\(entry.speciesIDs.count) species")
        }
        parts.append("placed to \(entry.bestRank.displayName.lowercased())")
        return parts.joined(separator: " · ")
    }
}

/// What is out this month, and what the garden is missing.
struct BloomPromptCard: View {

    let prompt: BloomPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(prompt.headline, systemImage: "camera.macro")
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.notYetPhotographed.isEmpty {
                Text("Worth looking for")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(prompt.notYetPhotographed.prefix(5), id: \.id) { species in
                    HStack {
                        Text(species.commonName).font(.subheadline)
                        if species.isKeystone {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Theme.queen)
                                .imageScale(.small)
                                .accessibilityLabel("keystone")
                        }
                        Spacer()
                        Text(species.family.commonName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !prompt.missingFamilies.isEmpty {
                Text("Families flowering now that the garden has none of: \(prompt.missingFamilies.map(\.commonName).spokenList).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}
