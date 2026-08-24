//
//  ContentView.swift
//  FlowerPower
//
//  Four places, matching the four things a player does: check on the colony,
//  look inside the nest, see where the forage is, and go photograph more.
//

import SwiftUI
import FlowerPowerCore

struct ContentView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .colony
    @State private var isCapturing = false

    enum Tab: Hashable {
        case colony, nest, map, garden
    }

    var body: some View {
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
        .sheet(isPresented: $isCapturing) {
            CaptureView()
        }
        .sheet(isPresented: hasPendingReport) {
            if let report = store.pendingReport {
                CatchUpReportView(report: report) { store.dismissReport() }
            }
        }
        .task {
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
            @unknown default:
                break
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
