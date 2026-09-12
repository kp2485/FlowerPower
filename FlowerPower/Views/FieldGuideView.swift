//
//  FieldGuideView.swift
//  FlowerPower
//
//  The whole catalogue, whether or not the player has found it.
//
//  The collection screen shows the shelf with spaces on it. This is the book
//  that says what belongs in the spaces: thirty plants grouped by family, what
//  to look for, when each one flowers, and whether a honey bee can work it at
//  all. It is the screen somebody reads before going out, and the one that
//  answers "why did nothing happen when I photographed a foxglove".
//
//  Everything on the page is computed in `FieldGuide`, in the package, where
//  it is compiled and tested. The view arranges it and nothing more — the one
//  thing that could go wrong here and nowhere else is the arrangement.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct FieldGuideView: View {

    @Environment(GameStore.self) private var store
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.northern.rawValue

    @State private var search = ""

    private var hemisphere: Hemisphere { Hemisphere(rawValue: hemisphereRaw) ?? .northern }
    private var guide: FieldGuide { FieldGuide(patches: store.snapshot.patches) }
    private var season: Season { RealSeason.current(in: hemisphere) }

    var body: some View {
        List {
            if search.isEmpty {
                progress
                outNow
                families
            } else {
                matches
            }
        }
        .searchable(text: $search, prompt: "Flower, genus or family")
        .navigationTitle("Field Guide")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    GlossaryView()
                } label: {
                    Label("Glossary", systemImage: "character.book.closed")
                }
            }
        }
    }

    // MARK: - Sections

    private var progress: some View {
        Section {
            LabeledContent(
                "Photographed",
                value: "\(guide.photographedCount) of \(guide.speciesTotal)"
            )
        } footer: {
            Text("Every plant the game knows. A tick is one you have found; the rest are out there.")
        }
    }

    @ViewBuilder
    private var outNow: some View {
        let flowering = guide.inBloom(hemisphere: hemisphere)
        if !flowering.isEmpty {
            Section {
                ForEach(flowering.prefix(6)) { entry in
                    row(entry)
                }
            } header: {
                Label("In bloom now — \(season.displayName.lowercased())", systemImage: Theme.symbol(for: season))
            } footer: {
                Text("Best nectar first. These are the ones worth walking for this week.")
            }
        }
    }

    private var families: some View {
        ForEach(guide.families) { group in
            Section {
                ForEach(group.entries) { entry in
                    row(entry)
                }
            } header: {
                HStack {
                    Text(group.family.commonName)
                    Spacer()
                    Text(group.family.scientificName)
                        .font(.caption.italic())
                        .textCase(nil)
                }
            } footer: {
                Text(group.family.forageNote)
            }
        }
    }

    @ViewBuilder
    private var matches: some View {
        let results = guide.search(search)
        if results.isEmpty {
            Section {
                ContentUnavailableView.search(text: search)
            }
        } else {
            Section("Matches") {
                ForEach(results) { entry in
                    row(entry)
                }
            }
        }
    }

    // MARK: - A row

    private func row(_ entry: FieldGuideEntry) -> some View {
        NavigationLink {
            FieldGuideDetailView(entry: entry, hemisphere: hemisphere)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if entry.hasBeenPhotographed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.healthy)
                            .imageScale(.small)
                            .accessibilityLabel("Photographed")
                    }
                    Text(entry.commonName)
                        .font(.body)
                    if entry.isKeystone {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Theme.queen)
                            .imageScale(.small)
                            .accessibilityLabel("Keystone flower")
                    }
                }

                Text(entry.scientificName)
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if entry.isInBloom(during: season) {
                        badge("In bloom", tint: Theme.honey)
                    }
                    if !entry.canReachNectar {
                        badge(entry.reach.displayName, tint: Theme.caution)
                    }
                    if entry.rarity != .common {
                        badge(entry.rarity.displayName, tint: Theme.queen)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - One plant

/// What to look for, when, and what the bees make of it.
///
/// The bottom half of this page is `FloralTraitsView`, unchanged: the corolla
/// drawn against a honey bee's reach is the same diagram whether the player
/// arrived from a photograph they took or from the guide. There is no second
/// telling of it here.
private struct FieldGuideDetailView: View {

    let entry: FieldGuideEntry
    let hemisphere: Hemisphere

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heading
                identification
                calendar
                verdict
                FloralTraitsView(species: entry.species)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(entry.commonName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.commonName)
                .font(.title2.weight(.semibold))
            Text(entry.scientificName)
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
            Text("\(entry.family.commonName) · \(entry.family.scientificName) · \(entry.rarity.displayName)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if entry.hasBeenPhotographed {
                Label("In your garden", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.healthy)
                    .padding(.top, 2)
            }

            if entry.isKeystone {
                Label(
                    "A keystone plant: it flowers when the colony has few other options, which makes it worth more than its yield alone.",
                    systemImage: "star.fill"
                )
                .font(.caption)
                .foregroundStyle(Theme.honey)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identification: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("What to look for", systemImage: "eye")
            Text(entry.fieldNote)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: The year

    private var calendar: some View {
        let months = Set(entry.bloomMonths(in: hemisphere))

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("When it flowers", systemImage: "calendar")

            HStack(spacing: 3) {
                ForEach(1...12, id: \.self) { month in
                    let flowering = months.contains(month)
                    Text(BloomCalendar.monthInitial(month))
                        .font(.caption2.weight(flowering ? .bold : .regular))
                        .foregroundStyle(flowering ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            flowering ? Theme.honey.opacity(0.3) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Flowers in \(entry.bloomMonths(in: hemisphere).map { BloomCalendar.monthName($0) }.spokenList)"
            )

            Text("\(entry.bloomSummary), in the \(hemisphere.rawValue) hemisphere.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Whether she can reach it

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Can a honey bee work it?", systemImage: "ruler")

            Label(entry.reach.displayName, systemImage: entry.canReachNectar ? "checkmark.circle" : "xmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(entry.canReachNectar ? Theme.healthy : Theme.caution)

            Text(entry.reach.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    NavigationStack {
        FieldGuideView()
            .environment(GameStore.preview())
    }
}
