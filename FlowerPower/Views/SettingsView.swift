//
//  SettingsView.swift
//  FlowerPower
//
//  Difficulty, moving house, and starting over.
//
//  Everything here drives a `GameStore` method that had no caller before:
//  `setDifficulty`, `relocateHive`, `startNewGame`. The engine grew three
//  presets and a relocation path that the player had no way to reach.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct SettingsView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isRelocating = false
    @State private var isConfirmingRestart = false
    @State private var isChoosingNewSite = false
    @State private var keepFlowers = true

    var body: some View {
        NavigationStack {
            Form {
                difficultySection
                nestSection
                gardenSection
                startOverSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isRelocating) {
                NewColonyView(reason: .relocating) { site in
                    store.relocateHive(to: HiveLocation(
                        coordinate: store.snapshot.nest.coordinate,
                        type: site
                    ))
                    isRelocating = false
                }
            }
            .sheet(isPresented: $isChoosingNewSite) {
                NewColonyView(reason: .firstColony) { site in
                    store.startNewGame(
                        at: HiveLocation(type: site),
                        keepingFlowers: keepFlowers
                    )
                    isChoosingNewSite = false
                    dismiss()
                }
            }
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        Section {
            ForEach(Difficulty.allCases) { difficulty in
                Button {
                    store.setDifficulty(difficulty.config)
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(difficulty.name)
                                .foregroundStyle(.primary)
                            Text(difficulty.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if difficulty.matches(store.currentConfig) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.honey)
                        }
                    }
                }
            }
        } header: {
            Text("Difficulty")
        } footer: {
            Text("Changes apply from now on. Across many simulated colonies, first-year survival runs at about 83% on Forgiving, 77% on Natural and 43% on Harsh.")
        }
    }

    // MARK: - Nest

    private var nestSection: some View {
        Section {
            LabeledContent("Site", value: store.snapshot.nest.siteType.displayName)
            LabeledContent("Comb") {
                Text("\(store.snapshot.nest.builtCells) of \(store.snapshot.nest.capacity) cells")
                    .monospacedDigit()
            }
            Button("Move the Hive") { isRelocating = true }
                .disabled(store.isCollapsed)
        } header: {
            Text("Nest")
        } footer: {
            Text("Comb space, not forage, is what limits how much a colony can store. A bigger cavity is the single biggest thing you can change.")
        }
    }

    // MARK: - Garden

    private var gardenSection: some View {
        Section {
            LabeledContent("Flowers photographed", value: "\(store.snapshot.patches.count)")
            LabeledContent("Still in bloom", value: "\(store.snapshot.patches.filter(\.isInBloom).count)")
            LabeledContent("Gone over", value: "\(store.snapshot.patches.filter(\.hasFaded).count)")
        } header: {
            Text("Garden")
        } footer: {
            Text("Flowers do not last. A patch you photograph is at its best for about two months and is gone a few months after that, so keep finding new ones.")
        }
    }

    // MARK: - Starting over

    private var startOverSection: some View {
        Section {
            Toggle("Keep my flowers", isOn: $keepFlowers)
            Button("Start a New Colony", role: .destructive) {
                isConfirmingRestart = true
            }
        } header: {
            Text("Start Over")
        } footer: {
            Text(keepFlowers
                 ? "The flowers you photographed carry across to the new colony. They are still growing where you found them."
                 : "Everything goes, including the flowers you have photographed. Your photos stay in your photo library.")
        }
        .confirmationDialog(
            "Abandon this colony?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("Start a New Colony", role: .destructive) {
                isChoosingNewSite = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This colony and everything it has built will be gone. There is no undo.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Day", value: "\(store.snapshot.day)")
            LabeledContent("Season", value: store.snapshot.season.rawValue.capitalized)
        } footer: {
            Text("One simulated hour passes every five real minutes, so a simulated day takes about two hours and a year about a month. The colony keeps going while the app is closed.")
        }
    }
}

// MARK: - Difficulty

/// The three engine presets, named for what they mean to a player rather than
/// for what they do to the constants.
enum Difficulty: String, CaseIterable, Identifiable {
    case gentle, standard, harsh

    var id: String { rawValue }

    var config: SimulationConfig {
        switch self {
        case .gentle: return .gentle
        case .standard: return .standard
        case .harsh: return .harsh
        }
    }

    var name: String {
        switch self {
        case .gentle: return "Forgiving"
        case .standard: return "Natural"
        case .harsh: return "Harsh"
        }
    }

    var detail: String {
        switch self {
        case .gentle:
            return "Richer forage, milder weather, fewer raiders. Colonies grow large and swarm often."
        case .standard:
            return "Tuned against real colony behaviour. Most colonies see their first spring; few see their third."
        case .harsh:
            return "A third less forage, hard winters, disease and predators pressing. Most colonies do not last the year."
        }
    }

    /// Compared on a couple of characteristic constants rather than by whole
    /// value, because the player may have a config that came from an older
    /// save and no longer equals any preset exactly.
    func matches(_ config: SimulationConfig) -> Bool {
        let mine = self.config
        return abs(mine.pathogenArrivalMultiplier - config.pathogenArrivalMultiplier) < 0.001
            && abs(mine.predatorStrength - config.predatorStrength) < 0.001
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(GameStore.preview())
}
