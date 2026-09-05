//
//  ForageMapView.swift
//  FlowerPower
//
//  Features.md asked for a MapView of the local area with the hive, the forage
//  and a fog of war. This is that map, with one change that turns out to matter
//  more than any of the rest: the flowers on it are real ones, in the real
//  places the player photographed them.
//
//  Distance is not cosmetic. A patch's yield falls off with the flight there and
//  back, and past about five miles a colony will not work it at all — so the
//  map is where the player sees why the roses at the end of the road are worth
//  more than the meadow two villages over.
//

import SwiftUI
import MapKit
import FlowerPowerCore
import FlowerPowerGame

struct ForageMapView: View {

    @Environment(GameStore.self) private var store

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedPatch: PatchSummary?

    private var snapshot: ColonySnapshot { store.snapshot }

    private var locatedPatches: [PatchSummary] {
        snapshot.patches.filter { $0.coordinate != nil }
    }

    private var unlocatedPatches: [PatchSummary] {
        snapshot.patches.filter { $0.coordinate == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locatedPatches.isEmpty && hiveCoordinate == nil {
                    MapUnavailableView(unlocatedCount: unlocatedPatches.count)
                } else {
                    mapContent
                }
            }
            .navigationTitle("Forage")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Centre on Hive", systemImage: "location.fill") {
                        centreOnHive()
                    }
                    .disabled(hiveCoordinate == nil)
                }
            }
            .sheet(item: $selectedPatch) { patch in
                PatchDetailView(patch: patch)
                    .presentationDetents([.medium])
            }
        }
    }

    private var mapContent: some View {
        Map(position: $camera, selection: Binding(
            get: { selectedPatch?.id },
            set: { id in selectedPatch = snapshot.patches.first { $0.id == id } }
        )) {
            if let hiveCoordinate {
                Annotation("The Hive", coordinate: hiveCoordinate) {
                    HiveMarker()
                }
                .annotationTitles(.hidden)

                // The colony's practical working range.
                MapCircle(center: hiveCoordinate, radius: FlowerPatch.maximumForagingRange)
                    .foregroundStyle(Theme.honey.opacity(0.06))
                    .stroke(Theme.honey.opacity(0.35), lineWidth: 1)
            }

            ForEach(locatedPatches) { patch in
                if let coordinate = patch.coordinate.map(CLLocationCoordinate2D.init) {
                    Annotation(patch.speciesName, coordinate: coordinate) {
                        PatchMarker(patch: patch)
                    }
                    .tag(patch.id)
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            if !unlocatedPatches.isEmpty {
                UnlocatedBanner(count: unlocatedPatches.count)
            }
        }
    }

    private var hiveCoordinate: CLLocationCoordinate2D? {
        snapshot.nest.coordinate.map(CLLocationCoordinate2D.init)
    }

    private func centreOnHive() {
        guard let hiveCoordinate else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: hiveCoordinate,
                latitudinalMeters: 3_000,
                longitudinalMeters: 3_000
            ))
        }
    }
}

// MARK: - Markers

private struct HiveMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.propolis)
                .frame(width: 36, height: 36)
            Image(systemName: "house.fill")
                .foregroundStyle(Theme.wax)
        }
        .shadow(radius: 3)
        .accessibilityLabel("The hive")
    }
}

private struct PatchMarker: View {

    let patch: PatchSummary

    private var tint: Color {
        guard patch.isWithinRange else { return .gray }
        guard patch.isInBloom else { return .gray.opacity(0.7) }
        switch patch.rarity {
        case .rare: return Theme.queen
        case .uncommon: return Theme.pollen
        case .common: return Theme.honey
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(patch.isInBloom ? 1 : 0.4))
                .frame(width: 28, height: 28)

            // The ring shows how much forage is left in the patch.
            Circle()
                .trim(from: 0, to: max(0.02, patch.remainingFraction))
                .stroke(.white.opacity(0.9), lineWidth: 2.5)
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)

            Image(systemName: patch.isIdentified ? "leaf.fill" : "questionmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(radius: 2)
        .accessibilityLabel(
            "\(patch.speciesName), \(Int(patch.remainingFraction * 100)) percent remaining"
        )
    }
}

// MARK: - Detail

private struct PatchDetailView: View {

    let patch: PatchSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Species") {
                        Text(patch.speciesName)
                            .foregroundStyle(patch.isIdentified ? .primary : .secondary)
                    }
                    LabeledContent("Rarity", value: patch.rarity.displayName)
                    LabeledContent("Distance") {
                        Text(Measurement(value: patch.distanceMetres, unit: UnitLength.meters),
                             format: .measurement(width: .abbreviated))
                    }
                    LabeledContent("Found", value: patch.discoveredAt.formatted(date: .abbreviated, time: .omitted))
                }

                Section("Right now") {
                    MeterView(
                        label: "Forage remaining",
                        value: patch.remainingFraction,
                        caption: "\(Int(patch.remainingFraction * 100))%",
                        tint: Theme.nectar,
                        symbolName: "drop.fill"
                    )
                    .listRowSeparator(.hidden)

                    LabeledContent("Bees working it", value: "\(patch.foragersWorkingIt)")

                    if !patch.isInBloom {
                        Label("Not in bloom this season", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(Theme.caution)
                    }
                    if !patch.isWithinRange {
                        Label("Beyond foraging range", systemImage: "location.slash")
                            .foregroundStyle(Theme.alarm)
                    }
                }

                if !patch.isIdentified {
                    Section {
                        Text("This one was not recognised, so your bees work it at reduced yield. A clearer photo of the same flower may identify it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(patch.speciesName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Empty and partial states

private struct MapUnavailableView: View {

    let unlocatedCount: Int

    var body: some View {
        ContentUnavailableView {
            Label("No Mapped Forage", systemImage: "map")
        } description: {
            if unlocatedCount > 0 {
                Text("You have \(unlocatedCount) flowers, but none of their photos carried a location. Allow location access in the camera to place them on the map.")
            } else {
                Text("Photograph flowers with location enabled and they will appear here, at the places you found them.")
            }
        }
    }
}

private struct UnlocatedBanner: View {

    let count: Int

    var body: some View {
        Label(
            "\(count) flowers have no location and are not shown. Your bees still forage them.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }
}

// MARK: - Bridging

extension CLLocationCoordinate2D {
    init(_ point: GeoPoint) {
        self.init(latitude: point.latitude, longitude: point.longitude)
    }
}

#Preview {
    ForageMapView()
        .environment(GameStore.preview())
}
