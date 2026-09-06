//
//  AlmanacView.swift
//  FlowerPower
//
//  The year, as the game wrote it.
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
                        Section {
                            ForEach(group.entries) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("Day \(entry.dayOfYear)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Label(entry.text, systemImage: symbol(for: entry.kind))
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } header: {
                            Label(group.season.rawValue.capitalized, systemImage: Theme.symbol(for: group.season))
                        }
                    }
                }
            }
        }
        .navigationTitle("Almanac")
        .toolbar {
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

    private struct SeasonGroup {
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

    private func symbol(for kind: AlmanacEntry.Kind) -> String {
        switch kind {
        case .season: return "calendar"
        case .forage: return "leaf.fill"
        case .queen: return "crown.fill"
        case .swarm: return "arrow.triangle.branch"
        case .threat: return "exclamationmark.shield.fill"
        case .disease: return "microbe.fill"
        case .stores: return "drop.fill"
        case .harvest: return "hand.raised.fill"
        case .colony: return "hexagon.fill"
        }
    }
}


// MARK: - The year, read back

/// The colony's own account of a year, which is what winter is for.
///
/// Built in the package as `YearInReview`, so what is shown here is the same
/// thing the tests check and not a second telling of it written in a view.
struct YearInReviewCard: View {

    let review: YearInReview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(review.headline, systemImage: "book.pages")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if review.notes.isEmpty {
                Text("Nothing worth writing down yet. There will be.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(review.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !review.queens.isEmpty {
                Text(review.queens.map(\.title).spokenList + " reigned.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
