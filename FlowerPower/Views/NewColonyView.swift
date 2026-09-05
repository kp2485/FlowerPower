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
            ? "Move Here"
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
                Text("Moving the colony to a new site.")
                    .font(.title3.weight(.semibold))
                Text("The bees come with you. Distances to every flower you have photographed are worked out again from the new position, so a move can put good forage out of reach.")
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

// MARK: - Plain-language site notes

private extension HiveLocationType {

    /// Written so a player can choose without reading the numbers. Each says
    /// the one thing that actually decides whether the site is a good idea.
    var summary: String {
        switch self {
        case .livingTreeCavity:
            return "What wild colonies choose when they can. Roomy, warm and easy to defend."
        case .fallenTree:
            return "Damp and closer to the ground, so more finds its way in, but a fair size."
        case .underTreeBranch:
            return "Open comb hanging in the air. Beautiful, tiny, cold and indefensible — a colony here will not see winter."
        case .cliff:
            return "Exposed rock. Cramped and draughty, though hard for anything heavy to reach."
        case .cave:
            return "The most room there is, and safe. Cold, though: it will cost honey to keep warm."
        case .insideWalls:
            return "Roomy, very warm and easily held. The best site in the game, if you do not mind the neighbours."
        case .humanStructure:
            return "A shed roof or a chimney. Warm and reasonably large."
        case .termiteMound:
            return "Thick earth walls hold heat well. Middling for space."
        case .animalBurrow:
            return "Underground, so warm-ish and well hidden, but damp and easy for a digger to reach."
        case .nestbox:
            return "Built for bees. Modest and unremarkable, which is the point."
        }
    }
}

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
