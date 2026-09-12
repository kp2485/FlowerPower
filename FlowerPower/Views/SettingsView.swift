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
    @State private var isAskingForForage = false
    @State private var isRereadingIntroduction = false

    @AppStorage("hiveHum") private var humEnabled = false
    @AppStorage("digestHour") private var digestHour = 8
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.northern.rawValue

    // The three kinds of notification, switched separately. Defaulting to true
    // is what makes an absent key mean "on", which is how
    // `BackgroundRefresh.isEnabled` reads them from the background task, where
    // there is no `@AppStorage` to be had.
    @AppStorage(BackgroundRefresh.Preference.decisions.rawValue)
    private var notifyDecisions = true
    @AppStorage(BackgroundRefresh.Preference.digest.rawValue)
    private var notifyDigest = true
    @AppStorage(BackgroundRefresh.Preference.news.rawValue)
    private var notifyNews = true

    var body: some View {
        NavigationStack {
            Form {
                difficultySection
                nestSection
                gardenSection
                rhythmSection
                notificationsSection
                startOverSection
                helpSection
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
            .sheet(isPresented: $isAskingForForage) {
                AskForForageView()
            }
            .sheet(isPresented: $isRereadingIntroduction) {
                // Not asking for notification permission a second time: iOS
                // shows that prompt once and afterwards the answer lives in
                // the system's own Settings, so a button here would do
                // nothing at all.
                OnboardingView(asksForNotifications: false) {
                    isRereadingIntroduction = false
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
            Text("Changes apply from now on. Over 200 simulated colonies, about 92% see their first spring on Forgiving, 89% on Natural and 64% on Harsh; by the second spring it is 60%, 66% and 14%. Forgiving is not safer over two years: well-fed colonies swarm more, and every swarm stakes the colony on a virgin queen's mating flight.")
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
            Text("Comb space, not forage, is what limits how much a colony can store. A bigger cavity is the single biggest thing you can change — but moving is absconding. The bees go; the comb, the stores and the brood stay behind.")
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

    // MARK: - Rhythm

    private var rhythmSection: some View {
        Section {
            Picker("Morning report", selection: $digestHour) {
                ForEach([6, 7, 8, 9, 10, 12, 18, 20], id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }

            Toggle("Winter runs at double speed", isOn: Binding(
                get: { store.winterSpeed > 1.5 },
                set: { store.winterSpeed = $0 ? SimClock.defaultWinterSpeed : 1 }
            ))

            Toggle("Hive hum", isOn: $humEnabled)

            Picker("Hemisphere", selection: $hemisphereRaw) {
                Text("Northern").tag(Hemisphere.northern.rawValue)
                Text("Southern").tag(Hemisphere.southern.rawValue)
            }

            Button("Ask a Friend for Forage") { isAskingForForage = true }
        } header: {
            Text("Rhythm")
        } footer: {
            Text("One report a day, at the hour you choose; decisions still arrive when they open. At double speed a winter lasts about four real days instead of seven. The hemisphere sets which flowers are in season for your walks.")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Notifications

    /// Three switches, because the three things the game sends are worth
    /// completely different amounts and a player who is tired of one should
    /// not have to silence all of them.
    ///
    /// A decision has a window on it: turned off, the colony still asks, and
    /// still falls back on instinct when nobody answers — the question simply
    /// waits on the dashboard until the player next opens the app, by which
    /// time it may have closed. That is the one worth keeping, and the footer
    /// says so rather than leaving it to be discovered.
    private var notificationsSection: some View {
        Section {
            Toggle("Decisions", isOn: $notifyDecisions)
            Toggle("Morning report", isOn: $notifyDigest)
            Toggle("Colony news", isOn: $notifyNews)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Decisions are a siege, swarm cells, a full nest, a swarm that has left, the autumn entrance — each with a window, each answerable from the notification itself. Colony news is everything else the colony does badly, including the day it ends. The morning report is one summary a day at the hour set above.")
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

    // MARK: - Help

    /// The introduction is three pages read once, before the player has seen
    /// any of the game, so it is exactly the sort of thing somebody wants back
    /// a week later. It is the same view, minus the permission prompt.
    private var helpSection: some View {
        Section {
            Button("How to Play") { isRereadingIntroduction = true }
            // The two reference books. They are also reachable from the
            // garden and the almanac, which is where a player is when a word
            // or a flower puzzles them; this is where they are found on
            // purpose.
            NavigationLink("Field Guide") { FieldGuideView() }
            NavigationLink("Glossary") { GlossaryView() }
            NavigationLink("About FlowerPower") { AboutView() }
        } header: {
            Text("Help")
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
            return "Richer forage, milder weather, fewer raiders. Colonies grow large and swarm often, which is its own risk."
        case .standard:
            return "Tuned against real colony behaviour. Most colonies see their first spring; few see their third."
        case .harsh:
            return "A third less forage, hard winters, disease and predators pressing. A third of colonies do not see their first spring, and few see a second."
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
