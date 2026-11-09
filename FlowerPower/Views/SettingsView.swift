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
import UserNotifications
import FlowerPowerCore
import FlowerPowerGame

struct SettingsView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// What iOS says, read each time this screen is looked at. Everything here
    /// was a toggle of the app's own, all on by default, so a player who
    /// tapped Not Now, or restored a backup before the prompt was ever
    /// reached, saw three switches on and never heard a thing.
    @State private var notificationStatus: UNAuthorizationStatus?

    @State private var isRelocating = false
    @State private var isConfirmingRestart = false
    @State private var isChoosingNewSite = false
    @State private var keepFlowers = true
    @State private var isAskingForForage = false
    @State private var isRereadingIntroduction = false
    @State private var preparedBackup: URL?
    @State private var backupFailure: String?
    /// What went into the prepared file, for the footer: how many of the
    /// garden's pictures came along and what the whole thing weighs.
    @State private var backupContents: BackupContents?
    @AppStorage("backupIncludesPhotographs") private var backupIncludesPhotographs = true

    private struct BackupContents: Equatable {
        let flowers: Int
        let photographs: Int
        let bytes: Int
    }

    @AppStorage("hiveHum") private var humEnabled = false
    @AppStorage("digestHour") private var digestHour = 8
    @AppStorage("hemisphere") private var hemisphereRaw = Hemisphere.likelyHere.rawValue

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
                backupSection
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
                NewColonyView(reason: .relocating, currentSite: store.snapshot.nest.siteType) { site in
                    store.relocateHive(to: HiveLocation(type: site))
                    isRelocating = false
                }
            }
            .sheet(isPresented: $isAskingForForage) {
                AskForForageView()
            }
            .sheet(isPresented: $isRereadingIntroduction) {
                // Not asking for notification permission here: the section
                // above is where that lives, and knows what iOS last said.
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
                                .accessibilityHidden(true)
                        }
                    }
                }
                // Which preset is in force was shown by a tick and said
                // nowhere, so a screen reader heard three identical rows.
                .accessibilityAddTraits(
                    difficulty.matches(store.currentConfig) ? [.isSelected] : []
                )
            }
        } header: {
            Text("Difficulty")
        } footer: {
            Text("Changes apply from now on. Of 200 simulated colonies in a tree cavity, about 98%, 92% and 69% saw their first spring on Forgiving, Natural and Harsh, and 90%, 76% and 12% their second. A smaller or more exposed site does worse.")
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
            // The one garden thing that is a setting rather than a reading.
            // This section was three counts the Garden tab and the dashboard
            // already show, and the button sat under "Rhythm", where nobody
            // would look for it.
            Button("Ask a Friend for Forage") { isAskingForForage = true }
        } header: {
            Text("Garden")
        } footer: {
            Text("A friend can send you a flower they photographed, and your bees will work it like one of yours.")
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
        } header: {
            Text("Rhythm")
        } footer: {
            Text("The morning report comes at the first chance after this hour. At double speed, winter takes about four real days instead of seven. The hemisphere picks which flowers are suggested for your walks.")
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
            switch notificationStatus {
            case .notDetermined:
                Button("Turn On Notifications") {
                    Task { @MainActor in
                        await BackgroundRefresh.requestNotificationPermission()
                        await readNotificationStatus()
                    }
                }
            case .denied:
                Label("Notifications are off for FlowerPower in iOS Settings.", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            default:
                EmptyView()
            }
            Group {
                Toggle("Decisions", isOn: $notifyDecisions)
                Toggle("Morning report", isOn: $notifyDigest)
                Toggle("Colony news", isOn: $notifyNews)
            }
            .disabled(notificationStatus == .notDetermined || notificationStatus == .denied)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Decisions can be answered from the notification itself. Colony news is anything else that goes badly; the morning report is one summary a day. iOS decides when the game may wake, so any of these can arrive hours late. The dashboard always has the whole of it.")
        }
        .task { @MainActor in await readNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in await readNotificationStatus() }
        }
    }

    @MainActor
    private func readNotificationStatus() async {
        notificationStatus = await BackgroundRefresh.notificationStatus()
    }

    // MARK: - Backup

    /// Getting the colony off the phone.
    ///
    /// The save is a file in an App Group container, which means it lives
    /// inside the app and nowhere else: there is no account and no sync, so
    /// deleting the app or moving to a phone without an iCloud device backup
    /// takes months of real walks with it. This is the way out. See
    /// `SaveArchive`.
    ///
    /// The file is written on the way in to this screen rather than on the
    /// tap, because `ShareLink` wants something to share before it is
    /// pressed, and it is rewritten whenever the colony moves on a day so the
    /// share sheet can never hand over yesterday's colony. The photographs
    /// are the slow part — each is read from the library and re-encoded
    /// small — so that happens off the main actor, and the toggle is there
    /// for a player who wants the colony alone in a file a message can carry.
    private var backupSection: some View {
        Section {
            Toggle("Include photographs", isOn: $backupIncludesPhotographs)
            if let preparedBackup {
                ShareLink(
                    item: preparedBackup,
                    preview: SharePreview("FlowerPower colony backup", image: Image(systemName: "hexagon.fill"))
                ) {
                    Label("Export a Backup", systemImage: "square.and.arrow.up")
                }
            } else if let backupFailure {
                Label(backupFailure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.alarm)
            } else {
                HStack {
                    Text("Export a Backup")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                        .accessibilityLabel("Packaging the colony up")
                }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(backupFooter)
        }
        // Keyed on the day and the toggle, so a colony that has moved on gets
        // a fresh file and one that has not is not re-encoded on every redraw.
        .task(id: "\(store.snapshot.day)|\(backupIncludesPhotographs)") { @MainActor in
            await prepareBackup()
        }
    }

    private var backupFooter: String {
        var lines = ["Opening the file on another phone replaces that phone's colony — it moves a colony rather than sharing one."]
        if let backupContents {
            let size = ByteCountFormatter.string(fromByteCount: Int64(backupContents.bytes), countStyle: .file)
            if backupIncludesPhotographs {
                let missing = backupContents.flowers - backupContents.photographs
                var line = "The whole colony, its garden and \(backupContents.photographs) of its \(backupContents.flowers) photographs, \(size)."
                if missing > 0 {
                    line += " \(missing) could not be read from your library and will show blank elsewhere."
                }
                lines.insert(line, at: 0)
            } else {
                lines.insert("The whole colony and its garden without the photographs, \(size). Elsewhere the flowers work as before with blank thumbnails.", at: 0)
            }
        }
        return lines.joined(separator: " ")
    }

    @MainActor
    private func prepareBackup() async {
        preparedBackup = nil
        backupFailure = nil
        backupContents = nil
        do {
            let patches = store.snapshot.patches
            var photographs: [SaveArchive.Photograph] = []
            if backupIncludesPhotographs {
                photographs = await Self.photographs(for: patches.map(\.photoLocalIdentifier))
            }
            guard !Task.isCancelled else { return }
            let data = try store.exportArchive(photographs: photographs)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(SaveArchive.suggestedFileName())
            try data.write(to: url, options: .atomic)
            preparedBackup = url
            backupContents = BackupContents(
                flowers: patches.count, photographs: photographs.count, bytes: data.count
            )
        } catch {
            backupFailure = "This colony could not be packaged up: "
                + error.localizedDescription
        }
    }

    /// Each photograph the garden can still find, made small and stripped
    /// of its metadata by the same path a shared flower takes. One that is
    /// not on this phone, or past the archive's per-picture cap even at its
    /// smallest, is left out rather than failing the backup.
    @concurrent
    nonisolated private static func photographs(for identifiers: [String]) async -> [SaveArchive.Photograph] {
        var photographs: [SaveArchive.Photograph] = []
        for identifier in identifiers {
            guard !Task.isCancelled else { return photographs }
            guard let original = await PhotoLoader.originalData(for: identifier),
                  let small = SharedImageStore.prepareForSharing(
                      original,
                      maximumDimension: 1_024,
                      quality: 0.8,
                      limit: SaveArchive.maximumPhotographBytes
                  )
            else { continue }
            photographs.append(SaveArchive.Photograph(identifier: identifier, jpeg: small))
        }
        return photographs
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
            LabeledContent("Day", value: "\(store.snapshot.displayDay)")
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
            return "Richer forage, milder weather, fewer raiders. Colonies grow large and swarm often, and most see several springs."
        case .standard:
            return "Tuned against real colony behaviour. Most colonies see two springs; fewer than half see a third."
        case .harsh:
            return "A third less forage, hard winters, disease and predators pressing. Nearly a third of colonies do not see their first spring, and few see a second."
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
