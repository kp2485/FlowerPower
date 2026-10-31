//
//  ContentView.swift
//  FlowerPower
//
//  Four places, matching the four things a player does: check on the colony,
//  look inside the nest, look at the ground around it, and go photograph more
//  flowers for it.
//
//  Plus one that is not a tab. When the colony is gone there is nothing to
//  look at in any of the four, so the whole interface gives way to choosing
//  where the next swarm settles. A dead colony used to leave the player on a
//  dashboard whose numbers had stopped moving, with no explanation and no way
//  to start again.
//

import SwiftUI
import TipKit
import FlowerPowerCore
import FlowerPowerGame

struct ContentView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .colony
    @State private var isCapturing = false

    /// The garden cell tapped on the map to start a capture, so the flower is
    /// planted there; and, once the capture is over, the cell the map should
    /// show blooming.
    @State private var plantingCell: HexCoordinate?
    @State private var bloomingCell: HexCoordinate?

    /// The colony as the player last left it, for the dashboard's "since you
    /// last looked" figures. See `LastLook`.
    @State private var lastLook: LastLook?
    @State private var isShowingSettings = false

    /// A flower somebody sent, waiting to be looked at. Held here rather than
    /// imported on arrival: content from outside the app gets shown to the
    /// player before it changes their game.
    @State private var incoming: FlowerShare?
    @State private var incomingSwarm: SwarmShare?
    @State private var incomingFailure: String?

    /// A colony backup the player opened. Carries its own failure case rather
    /// than sharing `incomingFailure`, because a restore that could not be
    /// read needs to say that nothing was replaced — see `OpenedBackup`.
    @State private var incomingBackup: OpenedBackup?

    /// Something opened from outside while another sheet was up. SwiftUI
    /// will not present a second sheet over the first and says nothing when
    /// it refuses, so a flower tapped in Messages while the catch-up report
    /// was showing simply never appeared — and could not be opened again
    /// until a relaunch, because `incoming` was already set. It waits here
    /// instead, and is shown as soon as the way is clear.
    @State private var waiting: Opened?

    private enum Opened {
        case flower(FlowerShare)
        case swarm(SwarmShare)
        case backup(OpenedBackup)
        case failure(String)
    }

    /// The last save problem the player closed, so the banner does not come
    /// straight back for the same one.
    @State private var dismissedError: String?

    @Environment(\.requestedAction) private var requestedAction
    @AppStorage("hiveHum") private var humEnabled = false

    enum Tab: Hashable {
        case colony, nest, world, garden
    }

    var body: some View {
        Group {
            if store.needsSetup {
                // A first launch. Nothing is saved until a site is chosen at
                // the end of this, so quitting half way through comes back
                // here rather than to a colony nobody picked.
                FirstRunView()
            } else if store.isCollapsed {
                NewColonyView(
                    reason: .afterCollapse,
                    epitaph: store.snapshot.epitaph
                ) { site in
                    store.startNewGame(at: HiveLocation(type: site))
                    selection = .colony
                }
            } else {
                tabs
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.lastError, error != dismissedError {
                ErrorBanner(message: error) { dismissedError = error }
            }
        }
        .onChange(of: isClearToPresent) { _, clear in
            guard clear, let opened = waiting else { return }
            waiting = nil
            // After the sheet that was in the way has finished going; one
            // presented during that animation is dropped like the first was.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                present(opened)
            }
        }
        // `.task` takes a @Sendable closure, which does not inherit the view's
        // main-actor isolation — so the hop has to be explicit to reach the
        // @MainActor store.
        .task(id: store.needsSetup) { @MainActor in
            await resume()
        }
        .onOpenURL { url in
            open(url)
        }
        .sheet(item: $incoming) { share in
            if share.isRequest {
                ReceiveRequestView(request: share)
                    .environment(store)
            } else {
                ReceiveFlowerView(share: share)
                    .environment(store)
            }
        }
        .sheet(item: $incomingSwarm) { share in
            ReceiveSwarmView(share: share)
                .environment(store)
        }
        .sheet(item: $incomingBackup) { opened in
            RestoreBackupView(opened: opened)
                .environment(store)
        }
        .onChange(of: requestedAction) { _, action in
            // Following a swarm needs a site chosen, so the notification
            // opened the app; the departed-swarm card on the dashboard is
            // where that choice lives.
            if action?.hasPrefix(NotificationActions.Action.followSwarm) ?? false { selection = .colony }
            // "Photograph a flower" from Siri, a Shortcut or Control Centre.
            // Matched on a prefix because the identifier carries a nonce —
            // see `PhotographFlowerIntent` for why asking twice has to look
            // like two different requests.
            // Not during the introduction: the tabs are not there yet, and the
            // flag used to sit set until setup finished and then open the
            // camera out of nowhere.
            if action?.hasPrefix(PhotographFlowerIntent.actionPrefix) ?? false, !store.needsSetup {
                plantingCell = nil
                isCapturing = true
            }
        }
        .onChange(of: humEnabled, initial: true) { _, enabled in
            if enabled, scenePhase == .active {
                HiveHum.shared.start()
            } else {
                HiveHum.shared.stop()
            }
        }
        .alert(
            "That flower could not be opened",
            isPresented: .init(
                get: { incomingFailure != nil },
                set: { if !$0 { incomingFailure = nil } }
            ),
            presenting: incomingFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await resume() }
                if humEnabled { HiveHum.shared.start() }
            case .inactive, .background:
                if phase == .background, !store.needsSetup {
                    LastLook.record(store.snapshot)
                }
                store.stopLiveUpdates()
                HiveHum.shared.stop()
                // Ask to be woken while the app is closed, so the colony the
                // watch and the complication show is not the one the player
                // last happened to look at.
                BackgroundRefresh.schedule()
            @unknown default:
                break
            }
        }
    }

    /// Brings the colony up to date and starts the live view. Called on every
    /// appearance and every return to the foreground.
    ///
    /// Not during setup: the colony that exists then is the placeholder
    /// `GameStore.load` invented, at a site nobody has chosen, and running it
    /// forward underneath the introduction would hand the player a catch-up
    /// report about a nest they have not seen. The store refuses to save or to
    /// tick while it needs setting up; this keeps it from being asked.
    private func resume() async {
        guard !store.needsSetup else { return }
        let look = LastLook.stored()
        // Off the main actor: after weeks away this is months of ticks, and
        // run here it froze the first screen long enough to risk the launch
        // watchdog.
        await store.catchUpInBackground()
        store.startLiveUpdates()

        // A short, quiet absence is told by the dashboard's figures rather
        // than a sheet over everything.
        withAnimation(.snappy) {
            lastLook = look.flatMap {
                Date().timeIntervalSince($0.takenAt) >= LastLook.worthShowingAfter ? $0 : nil
            }
        }
        if let report = store.pendingReport, !report.deservesASheet, lastLook != nil {
            store.dismissReport()
        }
        // See `SettingsTip`: it holds off until there is a flower in the
        // garden, so that it cannot out-run the camera tip on the first
        // screen a player ever sees.
        SettingsTip.hasPhotographed = !store.snapshot.patches.isEmpty
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ColonyDashboardView(onPhotograph: { plantingCell = nil; isCapturing = true })
                .tabItem { Label("Colony", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.colony)

            NestView()
                .tabItem { Label("Nest", systemImage: "hexagon.fill") }
                .tag(Tab.nest)

            // Between the nest and the garden, because that is where it sits
            // in the game: the nest is the inside, the world is the outside,
            // and the garden is the record of what has been carried between
            // them. The symbol is a cluster of cells rather than the Nest's
            // single filled hexagon — the same shape seen from above, and a
            // great deal more of it.
            WorldView(
                onPhotograph: { cell in
                    plantingCell = cell
                    isCapturing = true
                },
                bloomingCell: $bloomingCell
            )
                .tabItem { Label("World", systemImage: "circle.hexagongrid.fill") }
                .tag(Tab.world)

            GardenView(onPhotograph: { plantingCell = nil; isCapturing = true })
                .tabItem { Label("Garden", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.garden)
        }
        .tint(Theme.honey)
        // Each tab puts a `SettingsButton` in its own navigation bar. This
        // used to be one gear floated over the whole TabView at the top
        // trailing corner — which is exactly where every tab keeps its own
        // main action, so on the first Mac run the gear sat on top of the
        // camera button and hid the one thing the game asks the player to do.
        .environment(\.showSettings, { isShowingSettings = true })
        .environment(\.lastLook, lastLook)
        .sheet(isPresented: $isCapturing, onDismiss: {
            // The map checks the cell really was planted before it plays
            // anything, so a capture abandoned half way shows nothing.
            if let cell = plantingCell { bloomingCell = cell }
            plantingCell = nil
        }) {
            CaptureView(plantingAt: plantingCell)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: hasPendingReport) {
            if let report = store.pendingReport {
                CatchUpReportView(report: report) { store.dismissReport() }
            }
        }
    }

    /// Handles a `.flower`, `.swarm` or `.flowerhive` file the player opened
    /// from a message, from Files, or from anywhere else.
    ///
    /// The file arrives in a location the app is only lent access to, so it is
    /// read straight away rather than held as a URL. Nothing is imported or
    /// restored here — the receiving screen shows it first, which for a backup
    /// is not a nicety: opening one replaces the colony.
    private func open(_ url: URL) {
        let needsPermission = url.startAccessingSecurityScopedResource()
        defer { if needsPermission { url.stopAccessingSecurityScopedResource() } }

        let kind = url.pathExtension.lowercased()

        // A backup's own failure goes to its own screen, so the reassurance
        // that nothing was replaced comes with it. Everything else falls
        // through to the flower alert, as before.
        if kind == SaveArchive.fileExtension {
            do {
                deliver(.backup(.archive(
                    try SaveArchive.decoded(from: Data(contentsOf: url))
                )))
            } catch {
                deliver(.backup(.failure(error.localizedDescription)))
            }
            return
        }

        do {
            let data = try Data(contentsOf: url)
            if kind == SwarmShare.fileExtension {
                deliver(.swarm(try SwarmShare.decoded(from: data)))
            } else {
                deliver(.flower(try FlowerShare.decoded(from: data)))
            }
        } catch {
            deliver(.failure(error.localizedDescription))
        }
    }

    /// Whether nothing this view presents is in the way of another sheet.
    private var isClearToPresent: Bool {
        !isCapturing && !isShowingSettings && store.pendingReport == nil
            && incoming == nil && incomingSwarm == nil && incomingBackup == nil
            && incomingFailure == nil
    }

    /// Shows what was opened now, or as soon as the sheet in front closes.
    /// Opening a file is a deliberate act, so capture and settings are put
    /// away for it; an unread catch-up report is not, and is read first.
    private func deliver(_ opened: Opened) {
        if isClearToPresent {
            present(opened)
        } else {
            waiting = opened
            isCapturing = false
            isShowingSettings = false
        }
    }

    private func present(_ opened: Opened) {
        switch opened {
        case .flower(let share): incoming = share
        case .swarm(let share): incomingSwarm = share
        case .backup(let backup): incomingBackup = backup
        case .failure(let message): incomingFailure = message
        }
    }

    /// A binding rather than a plain flag, so dismissing the sheet by dragging
    /// also clears the report instead of leaving it to reappear.
    private var hasPendingReport: Binding<Bool> {
        Binding(
            get: { store.pendingReport != nil },
            set: { if !$0 { store.dismissReport() } }
        )
    }
}

// MARK: - A save problem

/// A save that could not be written or read. Rare, and worth saying: the
/// store keeps playing through it, and without this the player had no way
/// to know their progress was not being kept.
private struct ErrorBanner: View {

    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Settings, from every tab

/// The way into Settings, placed by each tab in its own navigation bar next
/// to that tab's own action, so the two cannot land on top of each other.
///
/// All four carry the Settings tip. TipKit shows a tip at one anchor at a
/// time, and the rule on `SettingsTip` still holds it back until there is a
/// flower in the garden.
struct SettingsButton: View {

    @Environment(\.showSettings) private var showSettings

    var body: some View {
        Button("Settings", systemImage: "gearshape.fill", action: showSettings)
            .popoverTip(AppTips.settings)
    }
}

private struct ShowSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Opens Settings. Set by `ContentView`, which owns the sheet.
    var showSettings: @MainActor () -> Void {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(GameStore.preview())
}
