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
//  fog to lift yet because there is nothing beyond them to find, and no wild
//  forage in the cells: what the map shows is the whole of what the engine
//  currently knows. Everything past the seven is paper.
//
//  What the map does not assume is that there are seven of them. It draws
//  whatever list of chunks it is handed, fits the frame to that list, and
//  keeps the home chunk apart only by its coordinate — so Phase 2, which has
//  an arbitrary number of discovered chunks and a ring of rumoured ones around
//  them, changes the caller and not the drawing. `drawRumoured(_:in:layout:)`
//  below is waiting for it.
//
//  Seven chunks fitted to a phone's width puts a cell at about 18 pt, which is
//  well under the 44 pt a finger wants, so the map zooms and pans: pinch,
//  drag, double tap, and a button in the navigation bar that puts the nest
//  back in the middle. The `Canvas` draws the same shapes it always did — the
//  zoom is arithmetic in `MapLayout`, not a transform over the drawing, so a
//  hexagon at four times the size is drawn at four times the size rather than
//  photographed and enlarged.
//

import Foundation
import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct WorldView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// How far in the map is and what it is looking at. Held here rather than
    /// in the map because the button that puts the nest back in the middle
    /// lives in the navigation bar, which is this view's.
    @State private var camera = MapCamera()

    private var snapshot: ColonySnapshot { store.snapshot }

    /// Every chunk the map draws.
    ///
    /// Phase 1 knows exactly seven and this is the line that says so. Phase 2
    /// replaces it with the discovered list — and nothing downstream of it
    /// needs to know that the list got longer.
    private var chunks: [Chunk] {
        guard let terrain = snapshot.terrain else { return [] }
        return [terrain.home] + terrain.neighbours
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let terrain = snapshot.terrain {
                        GroundHeader(terrain: terrain)

                        WorldMap(
                            chunks: chunks,
                            home: terrain.home.coordinate,
                            terrain: terrain,
                            snapshot: snapshot,
                            camera: $camera,
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

                ToolbarItem(placement: .topBarTrailing) {
                    if snapshot.terrain != nil {
                        Button("Centre on the Nest", systemImage: "scope") {
                            // The clamp in `MapLayout` does the rest: asking
                            // for the nest at the middle of the frame is asking
                            // for as much of that as the edges of the map allow,
                            // and the nest is always inside them.
                            withMapAnimation {
                                camera.focus = MapGeometry.point(for: .origin)
                            }
                        }
                        .disabled(camera.isFitted || camera.isOnNest)
                    }
                }
            }
            .sheet(item: $selectedPatch) { patch in
                FlowerDetailView(patch: patch)
            }
        }
    }

    /// Moving the camera is animated, because a map that jumps has to be
    /// re-read from scratch — unless the player has asked for less of that.
    private func withMapAnimation(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.3)) { change() }
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

/// The chunks, the garden and the nest, drawn in one `Canvas`.
///
/// A `Canvas` rather than a few hundred stacked `View`s: 259 cells is more
/// shapes than SwiftUI's layout system should be asked to carry on a screen
/// that redraws with every tick of the clock. The cost of that choice is that
/// the map is invisible to VoiceOver and deaf to hit-testing, so both are
/// supplied by hand below — `accessibilityRepresentation` for the first, and
/// arithmetic back from a tap point to a cell for the second. Neither of them
/// is affected by the zoom: the reading is taken from the terrain rather than
/// from the picture, and the hit-testing goes through the same `MapLayout`
/// that drew the frame it is testing against.
private struct WorldMap: View {

    /// Every chunk to draw, home included. The map takes the list as given —
    /// its extent, its aspect ratio and its pan limits are all computed from
    /// it — so a longer list is the whole of what Phase 2 has to supply.
    let chunks: [Chunk]

    /// Which of them the colony lives in. A coordinate rather than an index,
    /// because the list has no fixed order once it is longer than seven.
    let home: ChunkCoordinate

    let terrain: TerrainSummary
    let snapshot: ColonySnapshot

    @Binding var camera: MapCamera

    var onSelectPatch: (PatchSummary) -> Void
    var onSelectChunk: (Chunk?) -> Void
    var onPhotograph: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where a pan started from, so that a drag is measured from the place the
    /// finger went down rather than accumulated frame by frame.
    @State private var panAnchor: CGPoint?
    /// The same for a pinch: `MagnifyGesture` reports a multiple of the zoom
    /// the gesture began at.
    @State private var zoomAnchor: CGFloat?

    /// The box the chunks fill, in units of one hexagon's radius. Everything
    /// else — the frame's shape, the fit, how far the map may be dragged —
    /// comes from this one rectangle.
    private var bounds: CGRect { MapGeometry.bounds(for: chunks.map(\.coordinate)) }

    var body: some View {
        let bounds = self.bounds

        GeometryReader { geometry in
            let layout = MapLayout(
                size: geometry.size,
                bounds: bounds,
                zoom: camera.zoom,
                focus: camera.focus ?? CGPoint(x: bounds.midX, y: bounds.midY)
            )

            MapCanvas(
                zoom: layout.zoom,
                focusX: layout.focus.x,
                focusY: layout.focus.y,
                bounds: bounds,
                draw: draw
            )
            .onTapGesture(count: 2) { point in
                doubleTap(at: point, layout: layout)
            }
            .onTapGesture { point in
                handleTap(at: point, layout: layout)
            }
            .simultaneousGesture(pinch(layout: layout, size: geometry.size))
            // Only when there is somewhere to go. At the fit the map fills the
            // frame exactly and a drag has nothing to move, so the gesture is
            // left out of the way of the `ScrollView` this all sits in.
            .gesture(
                pan(layout: layout),
                including: layout.zoom > 1 ? .all : .subviews
            )
            .accessibilityRepresentation { reading }
        }
        // The shape of the ground, taken from the geometry rather than guessed,
        // so the map fits the width exactly and no cell is clipped. Seven
        // chunks come out very nearly square; a wider country later will come
        // out wider, and the frame will follow it.
        //
        // The floor is insurance rather than layout: a `GeometryReader` has no
        // ideal size of its own, so if this is ever proposed a height of
        // nothing the aspect ratio has nothing to work from. The map is drawn
        // to whatever frame it is given — `MapLayout` fits the arrangement to
        // the shorter side — so the worst case is a smaller map rather than a
        // wrong one.
        .aspectRatio(MapGeometry.aspect(of: bounds), contentMode: .fit)
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(Theme.comb.opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, layout: MapLayout) {
        // Everything past the known chunks: paper to the edge of the frame.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.fog))

        // The ground. Everything that is not home is washed out against it,
        // because the colony lives in one of these and only visits the others.
        for chunk in chunks {
            var colour = Theme.colour(for: chunk.biome)
            if chunk.coordinate != home { colour = colour.opacity(0.55) }
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

    /// Country the dancers have pointed at and nobody has walked over.
    ///
    /// Nothing calls this yet, because Phase 1 has no fog: there is nothing
    /// past the seven chunks to be rumoured about. It is here so that the
    /// drawing is not the part Phase 2 has to reopen — section 7 of
    /// docs/WORLD.md wants a rumoured chunk to show its outline and its
    /// guessed name and nothing else, and this is that outline.
    ///
    /// To use it: call it from the top of `draw(in:size:layout:)`, after the
    /// paper and before the ground, and add the same coordinates to the list
    /// `bounds` is computed from — `MapGeometry.bounds(for:)` takes
    /// coordinates rather than chunks precisely so that a rumour, which has no
    /// biome and no name to speak of, can still make room for itself in the
    /// frame.
    private func drawRumoured(
        _ rumoured: [ChunkCoordinate],
        in context: inout GraphicsContext,
        layout: MapLayout
    ) {
        for chunk in rumoured {
            for cell in chunk.cells {
                let path = layout.path(for: cell)
                // Paper, as the fog is, with the cell drawn in wax over it: a
                // stretch of country somebody has described, not one anybody
                // has seen. No biome colour, because the biome is a guess.
                context.fill(path, with: .color(Theme.fog))
                context.stroke(
                    path,
                    with: .color(Theme.wax),
                    lineWidth: max(0.5, layout.radius * 0.06)
                )
            }
        }
    }

    // MARK: Tapping

    /// A tap lands on whatever cell it is nearest to, and the cell decides
    /// what happens: a planted garden cell opens the flower, an empty one
    /// opens the camera, and anything in another chunk names it. A tap on home
    /// ground that is not garden clears the card — the header already says
    /// what home is.
    private func handleTap(at point: CGPoint, layout: MapLayout) {
        let cell = layout.cell(at: point, snappingTo: terrain.garden)

        if let garden = terrain.garden.first(where: { $0.cell == cell }) {
            if let patch = patch(in: garden) {
                onSelectPatch(patch)
            } else {
                onPhotograph()
            }
            return
        }

        let chunk = ChunkCoordinate.containing(cell)
        onSelectChunk(chunk == home ? nil : chunks.first { $0.coordinate == chunk })
    }

    /// Double tap goes in, at the place the finger landed rather than at the
    /// middle of the frame, which is what makes it useful for a cell near an
    /// edge. At the far end it is the way back out again: a second double tap
    /// on a map that is as far in as it goes returns the whole of it.
    private func doubleTap(at point: CGPoint, layout: MapLayout) {
        withMapAnimation {
            if layout.zoom >= layout.maximumZoom - 0.001 {
                camera.fit()
            } else {
                let zoom = layout.clamped(zoom: layout.zoom * 2)
                camera.focus = layout.clamped(focus: layout.focusHolding(point, atZoom: zoom))
                camera.zoom = zoom
            }
        }
    }

    private func patch(in garden: GardenCell) -> PatchSummary? {
        guard let id = garden.patchID else { return nil }
        return snapshot.patches.first { $0.id == id }
    }

    // MARK: Moving the map

    /// Dragging moves the world under the frame, an inch of finger to an inch
    /// of map. The limits are `MapLayout`'s: the map may not be dragged off
    /// its own edges, and since the nest is inside those edges it can always
    /// be brought back.
    private func pan(layout: MapLayout) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let start = panAnchor ?? layout.focus
                panAnchor = start
                camera.focus = layout.clamped(focus: CGPoint(
                    x: start.x - value.translation.width / layout.radius,
                    y: start.y - value.translation.height / layout.radius
                ))
            }
            .onEnded { _ in panAnchor = nil }
    }

    /// Pinching holds the ground under the two fingers still while the scale
    /// changes, which is the only version of this that does not feel like
    /// somebody else moving the map.
    private func pinch(layout: MapLayout, size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAnchor ?? layout.zoom
                zoomAnchor = start

                let zoom = layout.clamped(zoom: start * value.magnification)
                let anchor = CGPoint(
                    x: value.startAnchor.x * size.width,
                    y: value.startAnchor.y * size.height
                )
                camera.focus = layout.clamped(focus: layout.focusHolding(anchor, atZoom: zoom))
                camera.zoom = zoom
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    /// As in `WorldView`: a snap that is animated unless the player has asked
    /// for less movement. The pinch and the drag are never animated — they are
    /// already following a finger.
    private func withMapAnimation(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.3)) { change() }
        }
    }

    // MARK: Reading it aloud

    /// What the map is, for somebody who cannot see it.
    ///
    /// A `Canvas` has no accessibility tree at all, so this stands in for it:
    /// the ground the nest is on, the six stretches of country around it by
    /// name and direction, and every flower in the garden with the two numbers
    /// that matter — how far the bees fly to it and how much of it is left.
    /// Each one is a button, because each one is tappable on the map.
    ///
    /// None of it depends on the zoom. A map zoomed in on one corner still
    /// reads as the whole country, because what VoiceOver is being given is
    /// the terrain and not the picture of it.
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

/// The drawing on its own, so that the camera can be animated.
///
/// `Animatable` on a `View` is the one way to make a `Canvas` move smoothly:
/// SwiftUI interpolates `animatableData` and asks for `body` again at every
/// step of it, where a plain piece of `@State` would simply arrive at its new
/// value and the map would jump. The gestures do not need this — a finger
/// supplies its own intermediate values — but the centre-on-the-nest button
/// and the double tap do.
private struct MapCanvas: View, Animatable {

    var zoom: CGFloat
    var focusX: CGFloat
    var focusY: CGFloat

    let bounds: CGRect
    let draw: (inout GraphicsContext, CGSize, MapLayout) -> Void

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(zoom, AnimatablePair(focusX, focusY)) }
        set {
            zoom = newValue.first
            focusX = newValue.second.first
            focusY = newValue.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let layout = MapLayout(
                size: size,
                bounds: bounds,
                zoom: zoom,
                focus: CGPoint(x: focusX, y: focusY)
            )
            draw(&context, size, layout)
        }
    }
}

// MARK: - Geometry

/// Where the chunks sit, in units of one hexagon's radius.
///
/// Fixed by the lattice and nothing else: the shape of a chunk is the same for
/// every seed and every colony, so all of this is arithmetic on coordinates
/// with no terrain in sight. Pointy-top hexagons, which is why a chunk comes
/// out very slightly wider than it is tall.
private enum MapGeometry {

    static let sqrt3 = 3.0.squareRoot()

    /// A cell's centre, for a hexagon of radius 1.
    static func point(for cell: HexCoordinate) -> CGPoint {
        CGPoint(
            x: sqrt3 * (Double(cell.q) + Double(cell.r) / 2),
            y: 1.5 * Double(cell.r)
        )
    }

    /// How far a chunk reaches from its own centre, corners included.
    ///
    /// Closed form rather than a walk over all 37 cells: the cell of a chunk
    /// furthest east is the one at `q = +radius, r = 0`, which is `radius`
    /// units of `q + r/2` from the middle, and the one furthest south is at
    /// `r = +radius`. Add half a cell for the hexagon itself. Seven chunks is
    /// 259 cells and could be measured the slow way; a countryside of them
    /// could not, and this is measured on every frame of a drag.
    private static let chunkReach = CGSize(
        width: sqrt3 * (Double(ChunkCoordinate.radius) + 0.5),
        height: 1.5 * Double(ChunkCoordinate.radius) + 1
    )

    /// The box a list of chunks fills.
    ///
    /// Coordinates rather than `Chunk`s, so that a rumoured chunk — which has
    /// no biome worth drawing — can still make room for itself in the frame.
    static func bounds(for chunks: [ChunkCoordinate]) -> CGRect {
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity

        for chunk in chunks {
            let middle = point(for: chunk.centre)
            minX = min(minX, middle.x - chunkReach.width)
            maxX = max(maxX, middle.x + chunkReach.width)
            minY = min(minY, middle.y - chunkReach.height)
            maxY = max(maxY, middle.y + chunkReach.height)
        }

        // A map of nothing. Not reachable from a colony with terrain, but the
        // width of this rectangle is a divisor, so it is given a shape rather
        // than left infinite.
        guard minX <= maxX else {
            return CGRect(x: -chunkReach.width, y: -chunkReach.height,
                          width: chunkReach.width * 2, height: chunkReach.height * 2)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func aspect(of bounds: CGRect) -> CGFloat { bounds.width / bounds.height }
}

/// How far in the map is and what it is looking at.
///
/// Two numbers and nothing else, so that the state the player has built up by
/// pinching and dragging survives every redraw of a view that redraws with the
/// clock.
private struct MapCamera: Equatable {

    /// 1 is the whole map fitted to the frame; larger is further in. The
    /// ceiling belongs to `MapLayout`, which is the only thing that knows how
    /// big a cell that actually makes.
    var zoom: CGFloat = 1

    /// The point of the world held at the middle of the frame, in units of one
    /// hexagon's radius. Nil is "wherever fitting it puts it", which is what a
    /// colony's first look at its own country should be.
    var focus: CGPoint?

    /// The whole map, as it opens.
    var isFitted: Bool { zoom <= 1 && focus == nil }

    /// Already looking at the nest, so the button that does that has nothing
    /// to offer.
    var isOnNest: Bool { focus == MapGeometry.point(for: .origin) }

    mutating func fit() {
        zoom = 1
        focus = nil
    }
}

/// The map's arithmetic, in one place: cells to pixels for the drawing, and
/// pixels back to cells for the tapping, with the zoom and the pan folded into
/// both. The `Canvas` draws the same shapes at every zoom — a hexagon four
/// times the size is four times the size, not an enlargement of a small one.
private struct MapLayout {

    /// One hexagon's radius, in points, at the zoom the map is drawn at.
    let radius: CGFloat
    /// What that radius would be with the whole map fitted to the frame: the
    /// floor, because a map smaller than its frame is a map with paper around
    /// it and nothing gained.
    let fitRadius: CGFloat
    /// Where the nest — `HexCoordinate.origin` — sits in the frame.
    let centre: CGPoint
    /// The point of the world at the middle of the frame, after clamping.
    let focus: CGPoint

    private let size: CGSize
    private let bounds: CGRect

    /// As big as a cell is allowed to get. Two fingertips across: past this
    /// the map stops being a map and becomes one field at a time.
    static let largestCellWidth: CGFloat = 80

    /// What a finger wants, and so the size below which a tap needs help. The
    /// figure is the Human Interface Guidelines'.
    static let fingerWidth: CGFloat = 44

    init(size: CGSize, bounds: CGRect, zoom: CGFloat, focus wanted: CGPoint) {
        self.size = size
        self.bounds = bounds

        // Fit the whole arrangement; in practice the width binds, because the
        // frame is given the arrangement's own aspect ratio. Floored above
        // zero so that a frame measured before layout cannot divide by it.
        let fit = max(
            0.001,
            min(size.width / bounds.width, size.height / bounds.height)
        )
        fitRadius = fit
        radius = fit * min(max(zoom, 1), Self.maximumZoom(fitRadius: fit))
        focus = Self.clamped(focus: wanted, bounds: bounds, size: size, radius: radius)
        centre = CGPoint(
            x: size.width / 2 - focus.x * radius,
            y: size.height / 2 - focus.y * radius
        )
    }

    // MARK: The limits

    /// How far in the map is, as a multiple of the fit.
    var zoom: CGFloat { radius / fitRadius }

    /// How far in it may go. A map whose fitted cells are already generous —
    /// a single chunk, one day — gets less of this than one with a countryside
    /// in it, which is right: the ceiling is a size on the glass, not a number
    /// of doublings.
    var maximumZoom: CGFloat { Self.maximumZoom(fitRadius: fitRadius) }

    private static func maximumZoom(fitRadius: CGFloat) -> CGFloat {
        max(1, largestCellWidth / (MapGeometry.sqrt3 * fitRadius))
    }

    func clamped(zoom: CGFloat) -> CGFloat {
        min(max(zoom, 1), maximumZoom)
    }

    /// The width of a cell across its flat sides — the narrow way, and so the
    /// honest one to hold a fingertip against.
    var cellWidth: CGFloat { MapGeometry.sqrt3 * radius }

    /// Where the map is allowed to look.
    ///
    /// The rule is that the ground never leaves the frame: the map may be
    /// dragged until an edge of it reaches an edge of the frame and no
    /// further, and on an axis where the whole map already fits there is
    /// nothing to drag and it sits in the middle. That rule is what makes
    /// "the nest can always be brought back" true rather than hopeful — the
    /// nest is inside the bounds by construction, and every point inside the
    /// bounds is either reachable at the middle of the frame or visible from
    /// the nearest place the clamp allows.
    private static func clamped(focus: CGPoint, bounds: CGRect, size: CGSize, radius: CGFloat) -> CGPoint {
        func axis(_ value: CGFloat, from low: CGFloat, to high: CGFloat, frame: CGFloat) -> CGFloat {
            let half = frame / (2 * radius)
            let first = low + half
            let last = high - half
            guard first <= last else { return (low + high) / 2 }
            return min(max(value, first), last)
        }

        return CGPoint(
            x: axis(focus.x, from: bounds.minX, to: bounds.maxX, frame: size.width),
            y: axis(focus.y, from: bounds.minY, to: bounds.maxY, frame: size.height)
        )
    }

    func clamped(focus: CGPoint) -> CGPoint {
        Self.clamped(focus: focus, bounds: bounds, size: size, radius: radius)
    }

    /// The focus that would keep the ground currently under `point` under it
    /// at a different zoom. Both a pinch and a double tap are this: a scale
    /// about a place, rather than about the middle of the frame.
    func focusHolding(_ point: CGPoint, atZoom zoom: CGFloat) -> CGPoint {
        let target = fitRadius * zoom
        let unit = unitPoint(at: point)
        return CGPoint(
            x: unit.x - (point.x - size.width / 2) / target,
            y: unit.y - (point.y - size.height / 2) / target
        )
    }

    // MARK: Cells to pixels

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

    // MARK: Pixels back to cells

    /// Where a point in the frame falls, in units of one hexagon's radius.
    func unitPoint(at point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - centre.x) / radius, y: (point.y - centre.y) / radius)
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
        let unit = unitPoint(at: point)

        let r = unit.y / 1.5
        let q = unit.x / MapGeometry.sqrt3 - r / 2
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

    /// The cell a tap means, which is not always the cell it landed in.
    ///
    /// Fitted to a phone's width the whole country is drawn at about an 18 pt
    /// cell, less than half of what a finger can be asked to hit, and a player
    /// aiming at a flower and missing it by a few points gets the bare ground
    /// next door. So while a cell is under `fingerWidth` a tap that lands on
    /// nothing looks around: the nearest garden cell within half a radius
    /// beyond its own edge takes it. Zoomed in past a fingertip there is
    /// nothing to forgive and the rounding stands on its own, which matters
    /// because at that size the player can see exactly which cell they are
    /// pointing at and being moved off it would be wrong.
    ///
    /// Garden cells only. A tap near a chunk's edge that opens the wrong
    /// chunk's name costs a sentence; a tap that opens the camera instead of a
    /// flower, or the wrong flower, costs more.
    func cell(at point: CGPoint, snappingTo garden: [GardenCell]) -> HexCoordinate {
        let landed = cell(at: point)

        guard cellWidth < Self.fingerWidth,
              !garden.contains(where: { $0.cell == landed })
        else { return landed }

        // The edge is taken as the hexagon's inradius — its nearest point,
        // `√3/2` of a radius — so that the tolerance is the same in every
        // direction rather than reaching further towards the corners.
        var closest = radius * (MapGeometry.sqrt3 / 2 + 0.5)
        var best: HexCoordinate?

        for candidate in garden {
            let middle = self.point(for: candidate.cell)
            let distance = hypot(middle.x - point.x, middle.y - point.y)
            if distance <= closest {
                closest = distance
                best = candidate.cell
            }
        }

        return best ?? landed
    }
}

// MARK: - Preview

#Preview {
    WorldView(onPhotograph: {})
        .environment(GameStore.preview())
}
