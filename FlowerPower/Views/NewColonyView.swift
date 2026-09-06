//
//  NewColonyView.swift
//  FlowerPower
//
//  Choosing where a swarm settles.
//
//  Shown in two situations that want almost the same screen: the very first
//  launch, and the moment after a colony has died. The second is the one that
//  matters. Before this existed a dead colony simply stopped: the dashboard
//  read "Critical" for ever, the numbers never moved again, and the three
//  methods on the store that could have started another one — startNewGame,
//  relocateHive, setDifficulty — had no callers anywhere in the app.
//
//  It is deliberately not a defeat screen. Losing a colony is the ordinary
//  arc of beekeeping rather than a failure state, and the honest framing is
//  that a new swarm is looking for somewhere to live. The player's garden
//  comes with them, because those are photographs of real places they went
//  and the flowers are still growing there.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct NewColonyView: View {

    /// What brought the player here, which changes only the words.
    enum Reason {
        /// First launch. There has never been a colony.
        case firstColony
        /// The previous colony died.
        case afterCollapse
        /// The player chose to move an existing colony.
        case relocating
    }

    let reason: Reason
    /// Nil on a first launch, otherwise how the last colony ended, so the
    /// player is told what happened rather than left to guess.
    var epitaph: String?
    let onChoose: (HiveLocationType) -> Void

    @State private var selection: HiveLocationType = .livingTreeCavity

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Text("Where the bees settle decides almost everything. A big cavity holds more comb, which is the real limit on how much honey a colony can put away. A well-insulated one costs less honey to keep warm through winter. A small entrance can be held by a handful of guards.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(HiveLocationType.allCases, id: \.self) { site in
                        SiteRow(site: site, isSelected: site == selection)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = site }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onChoose(selection)
                } label: {
                    Label(actionTitle, systemImage: "hexagon.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }

    // MARK: - Words

    private var title: String {
        switch reason {
        case .firstColony: return "A New Colony"
        case .afterCollapse: return "Begin Again"
        case .relocating: return "Move the Hive"
        }
    }

    private var actionTitle: String {
        reason == .relocating
            ? "Abscond to Here"
            : "Settle Here"
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch reason {
            case .firstColony:
                Text("A swarm has left its old home and is looking for somewhere to live.")
                    .font(.title3.weight(.semibold))
                Text("Once they have settled, photograph the flowers you find and your bees will work them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .afterCollapse:
                Text("That colony is over.")
                    .font(.title3.weight(.semibold))
                if let epitaph {
                    Text(epitaph)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Most colonies end. A new swarm is looking for a home, and the flowers you photographed are still growing where you found them — your garden comes with you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .relocating:
                Text("Abandoning the nest for a new site.")
                    .font(.title3.weight(.semibold))
                Text("No colony can carry its comb. The adults go, with what honey they can hold in their crops; the stores, the comb and every larva stay behind. They arrive as a swarm does and start again. Distances to your flowers are worked out from the new position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - One site

private struct SiteRow: View {

    let site: HiveLocationType
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Theme.honey : .secondary)
                .imageScale(.large)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(site.displayName)
                        .font(.headline)
                    Spacer()
                    Text("\(site.maximumCells) cells")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(site.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    Trait(label: "Room", value: roomFraction, tint: Theme.comb)
                    Trait(label: "Warmth", value: site.insulation, tint: Theme.honey)
                    Trait(label: "Safety", value: site.defensibility, tint: Theme.healthy)
                }
            }
        }
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(isSelected ? Theme.honey : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Comb capacity as a fraction of the roomiest site there is, so the three
    /// meters are read on the same scale.
    private var roomFraction: Double {
        let largest = HiveLocationType.allCases.map(\.maximumCells).max() ?? 1
        return Double(site.maximumCells) / Double(largest)
    }
}

private struct Trait: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(.quaternary)
                .frame(width: 54, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: 54 * min(1, max(0, value)), height: 5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

// The plain-language site notes moved into the package as
// `HiveLocationType.summary`. They were an exhaustive switch over an engine
// type in a file nothing here can compile, which is exactly the shape of the
// `SimEvent.narration` bug — add a site and one screen silently describes it
// as nothing. `SymbolTests` now checks every site has a sentence.

// MARK: - Preview

#Preview("First colony") {
    NewColonyView(reason: .firstColony) { _ in }
}

#Preview("After a collapse") {
    NewColonyView(
        reason: .afterCollapse,
        epitaph: "The queen failed to return from her mating flight, and the colony had no eggs left to raise another."
    ) { _ in }
}
