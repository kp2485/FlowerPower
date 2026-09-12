//
//  ContentView.swift
//  FlowerPower
//
//  Four places, matching the four things a player does: check on the colony,
//  look inside the nest, see where the forage is, and go photograph more.
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
    @State private var isShowingSettings = false

    /// A flower somebody sent, waiting to be looked at. Held here rather than
    /// imported on arrival: content from outside the app gets shown to the
    /// player before it changes their game.
    @State private var incoming: FlowerShare?
    @State private var incomingSwarm: SwarmShare?
    @State private var incomingFailure: String?

    @Environment(\.requestedAction) private var requestedAction
    @AppStorage("hiveHum") private var humEnabled = false

    enum Tab: Hashable {
        case colony, nest, map, garden
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
        // `.task` takes a @Sendable closure, which does not inherit the view's
        // main-actor isolation — so the hop has to be explicit to reach the
        // @MainActor store.
        .task { @MainActor in
            resume()
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
        .onChange(of: requestedAction) { _, action in
            // Following a swarm needs a site chosen, so the notification
            // opened the app; the departed-swarm card on the dashboard is
            // where that choice lives.
            if action == NotificationActions.Action.followSwarm { selection = .colony }
            // "Photograph a flower" from Siri, a Shortcut or Control Centre.
            // Matched on a prefix because the identifier carries a nonce —
            // see `PhotographFlowerIntent` for why asking twice has to look
            // like two different requests.
            if action?.hasPrefix(PhotographFlowerIntent.actionPrefix) ?? false { isCapturing = true }
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
                resume()
                if humEnabled { HiveHum.shared.start() }
            case .inactive, .background:
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
    private func resume() {
        guard !store.needsSetup else { return }
        store.catchUp()
        store.startLiveUpdates()
        // See `SettingsTip`: it holds off until there is a flower in the
        // garden, so that it cannot out-run the camera tip on the first
        // screen a player ever sees.
        SettingsTip.hasPhotographed = !store.snapshot.patches.isEmpty
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ColonyDashboardView(onPhotograph: { isCapturing = true })
                .tabItem { Label("Colony", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.colony)

            NestView()
                .tabItem { Label("Nest", systemImage: "hexagon.fill") }
                .tag(Tab.nest)

            ForageMapView()
                .tabItem { Label("Forage", systemImage: "map.fill") }
                .tag(Tab.map)

            GardenView(onPhotograph: { isCapturing = true })
                .tabItem { Label("Garden", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.garden)
        }
        .tint(Theme.honey)
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .tint(Theme.honey)
            .padding(.trailing, 16)
            .accessibilityLabel("Settings")
            .popoverTip(Tips.settings)
        }
        .sheet(isPresented: $isCapturing) {
            CaptureView()
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

    /// Handles a `.flower` file the player opened from a message.
    ///
    /// The file arrives in a location the app is only lent access to, so it is
    /// read straight away rather than held as a URL. Nothing is imported here
    /// — `ReceiveFlowerView` shows it first.
    private func open(_ url: URL) {
        let needsPermission = url.startAccessingSecurityScopedResource()
        defer { if needsPermission { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == SwarmShare.fileExtension {
                incomingSwarm = try SwarmShare.decoded(from: data)
            } else {
                incoming = try FlowerShare.decoded(from: data)
            }
        } catch {
            incomingFailure = error.localizedDescription
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

// MARK: - Preview

#Preview {
    ContentView()
        .environment(GameStore.preview())
}
