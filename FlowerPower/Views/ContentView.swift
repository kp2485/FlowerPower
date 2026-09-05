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
import FlowerPowerCore
import FlowerPowerGame

struct ContentView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .colony
    @State private var isCapturing = false
    @State private var isShowingSettings = false

    enum Tab: Hashable {
        case colony, nest, map, garden
    }

    var body: some View {
        Group {
            if store.isCollapsed {
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
            store.catchUp()
            store.startLiveUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.catchUp()
                store.startLiveUpdates()
            case .inactive, .background:
                store.stopLiveUpdates()
                // Ask to be woken while the app is closed, so the colony the
                // watch and the complication show is not the one the player
                // last happened to look at.
                BackgroundRefresh.schedule()
            @unknown default:
                break
            }
        }
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
