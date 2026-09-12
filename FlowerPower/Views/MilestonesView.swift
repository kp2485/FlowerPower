//
//  MilestonesView.swift
//  FlowerPower
//
//  The things this colony did for the first time.
//
//  A page of badges, and the unearned ones are shown too — dimmed, but named.
//  That is deliberate and it is most of the value of the screen: a grid of
//  only what you have done is a trophy cabinet, while a grid with spaces in it
//  is the same gentlest-possible nudge that `CollectionView` makes with its
//  missing families. "Something out all year" sitting greyed out is how a
//  player finds out that winter flowers exist.
//
//  Nothing is computed here. The titles, the sentences and the symbols all
//  live in the package — see `Milestones.swift` and `Symbols.swift` — because
//  they are exhaustive switches over an engine type and this file has never
//  been near a compiler.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct MilestonesView: View {

    @Environment(GameStore.self) private var store

    /// Which badge's sentence is being read. `Milestone` is not `Identifiable`
    /// — it is a plain engine enum and should stay one — so the sheet is
    /// presented through a wrapper rather than by widening the package's type
    /// for one screen's convenience.
    @State private var reading: Reading?

    private struct Reading: Identifiable {
        let milestone: Milestone
        let day: Int?
        var id: String { milestone.rawValue }
    }

    private var milestones: Milestones { store.milestones }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Milestone.allCases, id: \.self) { milestone in
                        let day = milestones.day(of: milestone)
                        Button {
                            reading = Reading(milestone: milestone, day: day)
                        } label: {
                            BadgeTile(milestone: milestone, dayEarned: day)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Milestones")
        .sheet(item: $reading) { reading in
            BadgeDetail(milestone: reading.milestone, dayEarned: reading.day)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(milestones.count) of \(Milestone.allCases.count)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.honey)

            Text(milestones.isEmpty
                 ? "Nothing yet. Photograph a flower and the first of these is yours."
                 : "Firsts belong to this colony. A new colony earns its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One badge

private struct BadgeTile: View {

    let milestone: Milestone
    let dayEarned: Int?

    private var isEarned: Bool { dayEarned != nil }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.badgeFill(earned: isEarned))
                    .frame(width: 56, height: 56)

                Image(systemName: milestone.symbolName)
                    .font(.title3)
                    .foregroundStyle(Theme.badgeGlyph(earned: isEarned))
            }

            Text(milestone.title)
                .font(.caption.weight(isEarned ? .medium : .regular))
                .foregroundStyle(isEarned ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            if let dayEarned {
                Text(dayLabel(dayEarned))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                // Keeps every tile the same height, so the grid does not
                // shuffle as badges are earned.
                Text(" ")
                    .font(.caption2)
                    .hidden()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .opacity(isEarned ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(milestone.title)
        .accessibilityValue(isEarned
                            ? "Earned on day \(dayEarned ?? 0)"
                            : "Not yet earned")
        .accessibilityHint(milestone.detail)
    }

    private func dayLabel(_ day: Int) -> String {
        let record = MilestoneRecord(milestone: milestone, day: day)
        return "Year \(record.year), day \(day % Season.daysPerYear + 1)"
    }
}

// MARK: - The sentence behind it

private struct BadgeDetail: View {

    let milestone: Milestone
    let dayEarned: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.badgeFill(earned: dayEarned != nil))
                        .frame(width: 96, height: 96)
                    Image(systemName: milestone.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(Theme.badgeGlyph(earned: dayEarned != nil))
                }
                .padding(.top, 24)

                Text(milestone.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(milestone.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let dayEarned {
                    let record = MilestoneRecord(milestone: milestone, day: dayEarned)
                    Label(
                        "Earned in \(record.season.displayName.lowercased()) of year \(record.year)",
                        systemImage: record.season.symbolName
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.honey)
                } else {
                    Text("Not yet.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
