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
//  Every family is a row that opens. Shut, it is the family's name and a
//  tally; open, it is which genera and which species the garden actually
//  holds — or, for one not yet found, which plants of that family the game
//  knows, which is the one useful thing a gap can say.
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
        BloomPrompt(
            hemisphere: hemisphere,
            patches: store.snapshot.patches,
            terrain: store.snapshot.terrain,
            wildPatches: store.snapshot.wildPatches
        )
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
                    FoundFamilyRow(entry: entry, tally: detail(entry))
                }
            }

            if !collection.missingFamilies.isEmpty {
                Section {
                    ForEach(collection.missingFamilies, id: \.self) { family in
                        MissingFamilyRow(family: family)
                    }
                } header: {
                    Text("Not yet found")
                } footer: {
                    Text("Open one to see which of its plants the game knows.")
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

    /// Whether the bees have anything of their own to fly to — a stand out in
    /// the country that nobody photographed.
    private var hasWildForage: Bool { !store.snapshot.wildPatches.isEmpty }

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
                // The gap is in the *garden*, and since the world was drawn
                // that is no longer the same thing as a gap in the forage: a
                // colony with wild ground around it has something to fly to
                // in a season the shelf has nothing for. Saying otherwise
                // would be telling the player their bees are starving while
                // the foragers are out on the heath.
                Text("Nothing in the garden flowers in \(collection.seasonsMissing.map { $0.rawValue }.spokenList). "
                     + (hasWildForage
                        ? "The bees are left with whatever they can find wild."
                        : "The colony has no forage then."))
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

// MARK: - A family, open and shut

/// A family the garden holds.
///
/// Shut it is the name and the tally; open it is the family's forage note and
/// the genera and species actually photographed. The note used to be on every
/// row at once, which made eighteen families eighteen paragraphs.
private struct FoundFamilyRow: View {

    let entry: BotanyCollection.FamilyEntry
    /// The counted line the collection already wrote.
    let tally: String

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.family.forageNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !genera.isEmpty {
                    LabeledContent("Genera") {
                        Text(genera.spokenList)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                }

                if !species.isEmpty {
                    LabeledContent("Named to species") {
                        Text(species.spokenList)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.family.commonName).font(.headline)
                    Spacer()
                    Text(entry.family.scientificName)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }
                Text(tally)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "Collapses the family" : "Expands the family")
        }
        .tint(Theme.honey)
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    /// Sorted, because a `Set`'s own order differs between runs and a list
    /// that reshuffles itself is a list nobody trusts.
    private var genera: [String] { entry.genera.sorted() }

    /// Catalogue identifiers turned back into names a person would use.
    private var species: [String] {
        entry.speciesIDs
            .compactMap { id in FlowerCatalogue.all.first { $0.id == id }?.commonName }
            .sorted()
    }
}

/// A family the garden has none of.
///
/// Open, it says what the game knows of that family — which is the only
/// useful thing an empty space can offer somebody about to go for a walk.
private struct MissingFamilyRow: View {

    let family: PlantFamily

    @State private var isExpanded = false

    private var members: [FlowerSpecies] {
        FlowerCatalogue.all
            .filter { $0.family == family }
            .sorted { $0.commonName < $1.commonName }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(family.forageNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(members, id: \.id) { species in
                    HStack {
                        Text(species.commonName).font(.caption)
                        if species.isKeystone {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Theme.queen)
                                .imageScale(.small)
                                .accessibilityLabel("keystone")
                        }
                        Spacer()
                        Text(species.bloomSeasons
                            .sorted { $0.rawValue < $1.rawValue }
                            .map(\.displayName)
                            .formatted(.list(type: .and)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(family.commonName).font(.subheadline)
                Spacer()
                Text("\(members.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(family.commonName)
            .accessibilityValue("\(members.count) plants the game knows, none found")
            .accessibilityHint(isExpanded ? "Collapses the family" : "Expands the family")
        }
        .tint(Theme.honey)
        .sensoryFeedback(.selection, trigger: isExpanded)
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

            // Where the flow is, out in the country. Its own line, above the
            // advice about the garden, because it is not advice: nothing is
            // being asked for. The bees have found heather and this says so,
            // and it is the one sentence in the game that gives a direction.
            if let wild = prompt.wildKeystone {
                Label(wild, systemImage: "location.north.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.wild)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
