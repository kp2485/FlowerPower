//
//  AlmanacView.swift
//  FlowerPower
//
//  The year, as the game wrote it.
//
//  Two things open here. The year's review is a card that starts as its
//  headline and unfolds into the notes and the queens, because in a busy year
//  it is a dozen sentences sitting above the thing the player came to read.
//  And a season is a section that can be folded away, so a winter's worth of
//  lines is one tap out of the way of the spring.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct AlmanacView: View {

    @Environment(GameStore.self) private var store
    @State private var year: Int?

    private var almanac: Almanac { store.snapshot.almanac }
    private var years: [Int] {
        Array(Set(almanac.entries.map(\.year))).sorted(by: >)
    }

    var body: some View {
        Group {
            if almanac.isEmpty {
                ContentUnavailableView(
                    "Nothing written yet",
                    systemImage: "book.closed",
                    description: Text("The almanac fills as the year goes by: the first flow, the first swarm cell, what came to the nest.")
                )
            } else {
                List {
                    Section {
                        YearInReviewCard(review: store.snapshot.review(year: shownYear))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    ForEach(groupedBySeason, id: \.season) { group in
                        SeasonSection(
                            group: group,
                            isCurrent: group.season == groupedBySeason.last?.season
                        )
                    }
                }
            }
        }
        .navigationTitle("Almanac")
        .toolbar {
            // Winter is the reading season, and the almanac is written in the
            // vocabulary the glossary explains — supersedure, dearth, a drone
            // layer. The definition should be one tap from the sentence. It
            // sits with the year picker rather than in the leading slot,
            // which on a pushed screen belongs to the back button.
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    GlossaryView()
                } label: {
                    Label("Glossary", systemImage: "character.book.closed")
                }
            }
            if years.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Year", selection: Binding(
                        get: { shownYear },
                        set: { year = $0 }
                    )) {
                        ForEach(years, id: \.self) { Text("Year \($0)").tag($0) }
                    }
                }
            }
        }
    }

    struct SeasonGroup {
        let season: Season
        let entries: [AlmanacEntry]
    }

    /// The year on the page: whichever the player picked, or the latest.
    private var shownYear: Int { year ?? almanac.latestYear }

    private var groupedBySeason: [SeasonGroup] {
        let selected = almanac.entries(inYear: shownYear)
        return Season.allCases.compactMap { season in
            let entries = selected.filter { $0.season == season }
            return entries.isEmpty ? nil : SeasonGroup(season: season, entries: entries)
        }
    }

}

// MARK: - One season

/// A season's lines, behind a row that folds them away.
///
/// The newest season is the one somebody opening the almanac wants, and in a
/// full year the three before it are sixty lines to scroll past to reach it.
/// So the seasons that have already been are shut, with their line count on
/// the row, and open on a tap.
///
/// A `DisclosureGroup` inside the section rather than an expandable `Section`:
/// a collapsible section only actually collapses in a sidebar-styled list,
/// and this is an inset-grouped one.
private struct SeasonSection: View {

    let group: AlmanacView.SeasonGroup

    @State private var isExpanded: Bool

    /// - Parameter isCurrent: whether this is the season the year has
    ///   reached, which is the one that starts open.
    init(group: AlmanacView.SeasonGroup, isCurrent: Bool) {
        self.group = group
        _isExpanded = State(initialValue: isCurrent)
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(group.entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text("Day \(entry.dayOfYear)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Label(entry.text, systemImage: entry.kind.symbolName)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } label: {
                HStack {
                    Label(
                        group.season.rawValue.capitalized,
                        systemImage: Theme.symbol(for: group.season)
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(group.entries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(group.season.rawValue.capitalized)
                .accessibilityValue("\(group.entries.count) lines")
                .accessibilityHint(isExpanded ? "Collapses the season" : "Expands the season")
            }
            .tint(Theme.honey)
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
    }
}

// MARK: - The year, read back

/// The colony's own account of a year, which is what winter is for.
///
/// Built in the package as `YearInReview`, so what is shown here is the same
/// thing the tests check and not a second telling of it written in a view.
///
/// The headline is always out; the notes are a tap away. A busy year's review
/// runs to a dozen sentences, and this card sits above the almanac itself —
/// the thing the player actually came to read.
struct YearInReviewCard: View {

    let review: YearInReview

    /// A year with nothing to say does not need a chevron on it.
    private var hasMore: Bool { !review.notes.isEmpty || !review.queens.isEmpty }

    @State private var isExpanded = false

    var body: some View {
        Group {
            if hasMore {
                DisclosureGroup(isExpanded: $isExpanded) {
                    notes
                        .padding(.top, 10)
                } label: {
                    headline
                        .accessibilityHint(isExpanded ? "Collapses the year" : "Expands the year")
                }
                .tint(Theme.honey)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    headline
                    Text("Nothing worth writing down yet. There will be.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    private var headline: some View {
        Label(review.headline, systemImage: "book.pages")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(review.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !review.queens.isEmpty {
                Text(review.queens.map(\.title).spokenList + " reigned.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}
