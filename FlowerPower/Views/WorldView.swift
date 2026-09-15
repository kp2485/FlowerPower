//
//  WorldView.swift
//  FlowerPower
//
//  The ground the colony lives on: the stretch of country the nest stands in,
//  the six around it, and the garden the player has planted in between.
//
//  This is the screen that makes distance mean something. Every flower in the
//  game used to sit at the same nominal 800 m, because there was nothing to
//  say where it was; now a photograph goes into a cell of the garden at 200 m
//  or 400 m and the engine prices the trip accordingly. The map is where that
//  becomes visible — a garden with a shape, rather than a list.
//
//  Phase 1 of docs/WORLD.md draws exactly seven chunks and stops. There is no
//  fog to lift yet because there is nothing beyond them to find, no wild
//  forage in the cells, and no pan or zoom: what the map shows is the whole of
//  what the engine currently knows. Everything past the seven is paper.
//

import Foundation
import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct WorldView: View {

    @Environment(GameStore.self) private var store

    /// The same closure the Garden and the Colony use, so that an empty cell
    /// is a way into the camera rather than a dead end.
    var onPhotograph: () -> Void

    /// A flower the player tapped on the map. Opens the Garden's own detail
    /// sheet — one description of a patch, reached from two places.
    @State private var selectedPatch: PatchSummary?

    /// A neighbouring stretch of country the player tapped, shown in a card
    /// under the map rather than in a sheet: it is one sentence, and covering
    /// the map to read a sentence about it is the wrong trade.
    @State private var selectedChunk: Chunk?

    private var snapshot: ColonySnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let terrain = snapshot.terrain {
                        GroundHeader(terrain: terrain)

                        WorldMap(
                            terrain: terrain,
                            snapshot: snapshot,
                            onSelectPatch: { selectedPatch = $0 },
                            onSelectChunk: { selectedChunk = $0 },
                            onPhotograph: onPhotograph
                        )

                        if let chunk = selectedChunk {
                            NeighbourCard(chunk: chunk) { selectedChunk = nil }
                        }
                    } else {
                        // A colony with no terrain: a save from before the
                        // world existed that has somehow not been migrated.
                        // Nothing is drawn rather than something invented.
                        ContentUnavailableView(
                            "No Ground Yet",
                            systemImage: "circle.hexagongrid",
                            description: Text("This colony has no country around it to draw.")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(snapshot.terrain?.homeName ?? "World")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
            }
            .sheet(item: $selectedPatch) { patch in
                FlowerDetailView(patch: patch)
            }
        }
    }
}

// MARK: - What the ground is

/// The name of the country, what it is like, and how the garden stands in it.
private struct GroundHeader: View {

    let terrain: TerrainSummary

    private var planted: Int { terrain.garden.count - terrain.emptyCells.count }

    /// How the garden is doing, and what would make it bigger.
    ///
    /// The milestone titles are taken from `Milestone` rather than written out
    /// again, so the sentence here and the badge in the Milestones screen
    /// cannot drift apart.
    private var gardenLine: String {
        let counted = "\(planted) of \(terrain.garden.count) cells planted"
        switch terrain.gardenRings {
        case 1:
            return counted + " — ring 2 opens at "
                + Milestone.tenFlowers.title.lowercased() + "."
        case 2:
            return counted + " — ring 3 opens at "
                + Milestone.tenFamilies.title.lowercased() + "."
        default:
            return counted + ". The garden is as wide as it goes."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(terrain.homeBiome.displayName)
                .font(.headline)

            Text(terrain.homeBiome.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(gardenLine, systemImage: "leaf.fill")
                .font(.caption)
                .foregroundStyle(Theme.honey)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A neighbouring stretch of country, after a tap on it.
private struct NeighbourCard: View {

    let chunk: Chunk
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(chunk.name)
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(chunk.biome.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.colour(for: chunk.biome))

            Text(chunk.biome.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - The map

/// The seven chunks, the garden and the nest, drawn in one `Canvas`.
///
/// A `Canvas` rather than a few hundred stacked `View`s: 259 cells is more
/// shapes than SwiftUI's layout system should be asked to carry on a screen
/// that redraws with every tick of the clock. The cost of that choice is that
/// the map is invisible to VoiceOver and deaf to hit-testing, so both are
/// supplied by hand below — `accessibilityRepresentation` for the first, and
/// arithmetic back from a tap point to a cell for the second.
private struct WorldMap: View {

    let terrain: TerrainSummary
    let snapshot: ColonySnapshot

    var onSelectPatch: (PatchSummary) -> Void
    var onSelectChunk: (Chunk?) -> Void
    var onPhotograph: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = MapLayout(size: geometry.size)

            Canvas { context, size in
                draw(in: &context, size: size, layout: layout)
            }
            .onTapGesture { point in
                handleTap(at: point, layout: layout)
            }
            .accessibilityRepresentation { reading }
        }
        // Very nearly square, which is what seven hexagons of hexagons come
        // to. Taken from the geometry rather than guessed, so the map fits the
        // width exactly and no cell is clipped.
        //
        // The floor is insurance rather than layout: a `GeometryReader` has no
        // ideal size of its own, so if this is ever proposed a height of
        // nothing the aspect ratio has nothing to work from. The map is drawn
        // to whatever frame it is given — `MapLayout` fits the arrangement to
        // the shorter side — so the worst case is a smaller map rather than a
        // wrong one.
        .aspectRatio(MapGeometry.aspect, contentMode: .fit)
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(Theme.comb.opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, layout: MapLayout) {
        // Everything past the seven chunks: paper to the edge of the frame.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.fog))

        // The ground. Neighbours are washed out against home, because the
        // colony lives in one of these and only visits the others.
        for cell in terrain.home.coordinate.cells {
            context.fill(layout.path(for: cell), with: .color(Theme.colour(for: terrain.home.biome)))
        }
        for chunk in terrain.neighbours {
            let colour = Theme.colour(for: chunk.biome).opacity(0.55)
            for cell in chunk.coordinate.cells {
                context.fill(layout.path(for: cell), with: .color(colour))
            }
        }

        // The garden: every open cell outlined in wax, so a plantable cell
        // reads as somewhere to put something rather than as bare ground.
        for garden in terrain.garden {
            context.stroke(
                layout.path(for: garden.cell),
                with: .color(Theme.wax),
                lineWidth: max(1, layout.radius * 0.12)
            )
        }

        // What is planted. The wax dot underneath and the pollen dot over it
        // at the patch's vigour, so a stand going over fades to wax in place
        // rather than vanishing — which is the cue to go and photograph
        // another one.
        for garden in terrain.garden {
            guard let id = garden.patchID,
                  let patch = snapshot.patches.first(where: { $0.id == id })
            else { continue }

            let dot = layout.dot(at: garden.cell, fraction: 0.42)
            context.fill(Path(ellipseIn: dot), with: .color(Theme.wax))
            context.fill(
                Path(ellipseIn: dot),
                with: .color(Theme.pollen.opacity(max(0, min(1, patch.vigour))))
            )
        }

        // The nest, at the origin, in honey.
        let nest = layout.path(for: .origin)
        context.fill(nest, with: .color(Theme.honey))
        context.stroke(
            nest,
            with: .color(Theme.propolis),
            lineWidth: max(1, layout.radius * 0.12)
        )

        // The time of year, over all of it. Low enough to be a cast of light
        // rather than a filter: the rape field is only yellow in May, but the
        // map must still be readable in December.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Theme.colour(for: snapshot.season).opacity(0.12))
        )
    }

    // MARK: Tapping

    /// A tap lands on whatever cell it is nearest to, and the cell decides
    /// what happens: a planted garden cell opens the flower, an empty one
    /// opens the camera, and anything in a neighbouring chunk names it. A tap
    /// on home ground that is not garden clears the card — the header already
    /// says what home is.
    private func handleTap(at point: CGPoint, layout: MapLayout) {
        let cell = layout.cell(at: point)

        if let garden = terrain.garden.first(where: { $0.cell == cell }) {
            if let patch = patch(in: garden) {
                onSelectPatch(patch)
            } else {
                onPhotograph()
            }
            return
        }

        let chunk = ChunkCoordinate.containing(cell)
        onSelectChunk(terrain.neighbours.first { $0.coordinate == chunk })
    }

    private func patch(in garden: GardenCell) -> PatchSummary? {
        guard let id = garden.patchID else { return nil }
        return snapshot.patches.first { $0.id == id }
    }

    // MARK: Reading it aloud

    /// What the map is, for somebody who cannot see it.
    ///
    /// A `Canvas` has no accessibility tree at all, so this stands in for it:
    /// the ground the nest is on, the six stretches of country around it by
    /// name and direction, and every flower in the garden with the two numbers
    /// that matter — how far the bees fly to it and how much of it is left.
    /// Each one is a button, because each one is tappable on the map.
    @ViewBuilder private var reading: some View {
        VStack {
            Text("\(terrain.homeName), \(terrain.homeBiome.displayName.lowercased()). \(terrain.homeBiome.summary) The nest is at the centre.")

            ForEach(Array(terrain.neighbours.enumerated()), id: \.element.id) { index, chunk in
                Button {
                    onSelectChunk(chunk)
                } label: {
                    Text("\(chunk.name) to the \(Self.compass[index]), \(chunk.biome.displayName.lowercased()).")
                }
            }

            ForEach(planted) { cell in
                Button {
                    onSelectPatch(cell.patch)
                } label: {
                    Text(label(for: cell))
                }
            }

            if !terrain.emptyCells.isEmpty {
                Button {
                    onPhotograph()
                } label: {
                    Text("\(terrain.emptyCells.count) empty cells in the garden. Photograph a flower to plant one.")
                }
            }
        }
    }

    /// The six directions, in the order `HexCoordinate.directions` fixes them
    /// — east first, then clockwise with `r` increasing southward.
    private static let compass = [
        "east", "south-east", "south-west", "west", "north-west", "north-east"
    ]

    private func label(for planted: PlantedCell) -> String {
        let metres = Int(planted.garden.distanceMetres)
        let remaining = Int(planted.patch.remainingFraction * 100)
        return "\(planted.patch.speciesName), ring \(planted.garden.ring), "
            + "\(metres) metres from the nest, \(remaining) percent left."
    }

    /// A garden cell and the flower standing in it, paired up once so that
    /// neither the drawing nor the reading has to look a patch up twice.
    private struct PlantedCell: Identifiable {
        let garden: GardenCell
        let patch: PatchSummary
        var id: HexCoordinate { garden.cell }
    }

    private var planted: [PlantedCell] {
        terrain.garden.compactMap { garden in
            patch(in: garden).map { PlantedCell(garden: garden, patch: $0) }
        }
    }
}

// MARK: - Geometry

/// Where the seven chunks sit, in units of one hexagon's radius.
///
/// Fixed by the lattice and nothing else, so it is worked out once: the shape
/// of seven chunks is the same for every seed and every colony. Pointy-top
/// hexagons, which is why the arrangement comes out very slightly wider than
/// it is tall.
private enum MapGeometry {

    static let sqrt3 = 3.0.squareRoot()

    /// A cell's centre, for a hexagon of radius 1.
    static func point(for cell: HexCoordinate) -> CGPoint {
        CGPoint(
            x: sqrt3 * (Double(cell.q) + Double(cell.r) / 2),
            y: 1.5 * Double(cell.r)
        )
    }

    /// The box the seven chunks fill, corners included.
    static let bounds: CGRect = {
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity

        for chunk in [ChunkCoordinate.origin] + ChunkCoordinate.origin.neighbours {
            for cell in chunk.cells {
                let centre = point(for: cell)
                minX = min(minX, centre.x - sqrt3 / 2)
                maxX = max(maxX, centre.x + sqrt3 / 2)
                minY = min(minY, centre.y - 1)
                maxY = max(maxY, centre.y + 1)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }()

    static var aspect: CGFloat { bounds.width / bounds.height }
}

/// The map's arithmetic, in one place: cells to pixels for the drawing, and
/// pixels back to cells for the tapping.
private struct MapLayout {

    /// One hexagon's radius, in points.
    let radius: CGFloat
    /// Where the nest — `HexCoordinate.origin` — sits in the frame.
    let centre: CGPoint

    init(size: CGSize) {
        let bounds = MapGeometry.bounds
        // Fit the whole arrangement; in practice the width binds, because the
        // frame is given the arrangement's own aspect ratio. Floored above
        // zero so that a frame measured before layout cannot divide by it.
        let scale = max(
            0.001,
            min(size.width / bounds.width, size.height / bounds.height)
        )
        radius = scale
        centre = CGPoint(
            x: size.width / 2 - bounds.midX * scale,
            y: size.height / 2 - bounds.midY * scale
        )
    }

    func point(for cell: HexCoordinate) -> CGPoint {
        let unit = MapGeometry.point(for: cell)
        return CGPoint(x: centre.x + unit.x * radius, y: centre.y + unit.y * radius)
    }

    /// One hexagon, point upward — the shape of a comb cell turned on its end,
    /// with a vertex at the top and a flat side east and west.
    func path(for cell: HexCoordinate) -> Path {
        let middle = point(for: cell)
        var path = Path()
        for corner in 0..<6 {
            // Corners at 60° intervals starting 30° off the horizontal, which
            // is what puts a vertex at the top rather than a flat side.
            let angle = (Double(corner) * 60 - 30) * .pi / 180
            let position = CGPoint(
                x: middle.x + radius * cos(angle),
                y: middle.y + radius * sin(angle)
            )
            if corner == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        return path
    }

    /// The square a mark in a cell is drawn inside.
    func dot(at cell: HexCoordinate, fraction: CGFloat) -> CGRect {
        let middle = point(for: cell)
        let size = radius * fraction
        return CGRect(x: middle.x - size, y: middle.y - size, width: size * 2, height: size * 2)
    }

    /// The cell a point falls in.
    ///
    /// The inverse of `MapGeometry.point(for:)` gives fractional axial
    /// coordinates, which are then rounded in cube space: round all three of
    /// `q`, `r` and `s`, and give the one that moved furthest back whatever it
    /// takes to restore `q + r + s == 0`. Rounding the two axial coordinates
    /// on their own picks the wrong cell along every hexagon edge, which on a
    /// map of 259 of them is most of the map.
    func cell(at point: CGPoint) -> HexCoordinate {
        let x = (point.x - centre.x) / radius
        let y = (point.y - centre.y) / radius

        let r = y / 1.5
        let q = x / MapGeometry.sqrt3 - r / 2
        let s = -q - r

        var roundedQ = q.rounded()
        var roundedR = r.rounded()
        let roundedS = s.rounded()

        let driftQ = abs(roundedQ - q)
        let driftR = abs(roundedR - r)
        let driftS = abs(roundedS - s)

        if driftQ > driftR && driftQ > driftS {
            roundedQ = -roundedR - roundedS
        } else if driftR > driftS {
            roundedR = -roundedQ - roundedS
        }

        return HexCoordinate(q: Int(roundedQ), r: Int(roundedR))
    }
}

// MARK: - Preview

#Preview {
    WorldView(onPhotograph: {})
        .environment(GameStore.preview())
}
