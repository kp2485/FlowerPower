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

    /// Opens the camera. With a cell when an empty garden cell was tapped,
    /// so the flower is planted where the player pointed; without one from
    /// the button in the empty state.
    var onPhotograph: (HexCoordinate?) -> Void

    /// A cell just planted from the map, set once the camera closes. The map
    /// plays it blooming and clears it.
    @Binding var bloomingCell: HexCoordinate?

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

    /// A stand of something wild the player tapped. Shown in a card under the
    /// map beside the chunk's, for the same reason: it is three short facts,
    /// and a sheet to read three facts is the wrong trade.
    /// By identifier and looked up live, so its bloom and its count of bees
    /// follow the colony rather than stopping at the moment of the tap.
    @State private var selectedWildID: EntityID?

    private var selectedWild: PatchSummary? {
        snapshot.wildPatches.first { $0.id == selectedWildID }
    }

    /// Every chunk the map draws.
    ///
    /// Everything the colony has been to, in the order it came to know it —
    /// the home chunk and its six to begin with, and whatever the foragers and
    /// the scouts have added since. Nothing downstream of this needs to know
    /// that the list got longer: the frame, the fit and the pan limits are all
    /// measured from whatever it holds.
    private var chunks: [Chunk] {
        guard let terrain = snapshot.terrain else { return [] }
        return terrain.discovered
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
                            onSelectChunk: {
                                selectedChunk = $0
                                selectedWildID = nil
                            },
                            onSelectWild: {
                                selectedWildID = $0.id
                                selectedChunk = nil
                            },
                            onPhotograph: onPhotograph,
                            bloomingCell: $bloomingCell
                        )

                        if let wild = selectedWild {
                            WildStandCard(
                                patch: wild,
                                chunk: terrain.chunk(containing: wild.cell ?? .origin),
                                plantable: terrain.emptyCells.contains { $0.cell == wild.cell }
                                    ? { onPhotograph(wild.cell) } : nil
                            ) { selectedWildID = nil }
                        }

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
                        // At the fit the whole map is in frame, wherever the
                        // focus was left, so there is nothing for it to do.
                        .disabled(camera.zoom <= 1 || camera.isOnNest)
                    }
                }
            }
            // The cards are about ground the colony has just left behind.
            .onChange(of: store.colonyChanges) { _, _ in
                selectedChunk = nil
                selectedWildID = nil
            }
            .sheet(item: $selectedPatch) { patch in
                FlowerDetailView(patch: patch)
                    .childSheet()
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
    private var gardenLine: String {
        // Worked out from what the engine does: the flower that finds every
        // open ring full opens the next. This used to quote milestones that
        // rarely decide it, and to call a garden with no limit finished.
        "\(planted) of \(terrain.garden.count.counted("cell")) planted. "
            + "A new ring opens when these are full."
    }

    /// Where the scouting party is, when there is one out.
    private var scoutsLine: String {
        guard let days = terrain.scoutsDaysRemaining, days > 0 else {
            return "Scouts are out — back today."
        }
        return "Scouts are out — back in \(days.counted("day"))."
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

            // A tenth of the force is away, and the map is about to get
            // bigger. Under the header rather than over the map, because it
            // is a fact about the colony and not about the drawing.
            if terrain.scoutsOut {
                Label(scoutsLine, systemImage: "figure.walk.departure")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }

            Text(chunk.biome.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(chunk.biome.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A stand of something the bees found for themselves, after a tap on it.
///
/// Deliberately not the Garden's flower sheet: there is no photograph behind
/// it, no identification to argue with and nothing to share. What there is is
/// what a forager would report — what it is, where it is, whether it is out,
/// and how many of them are on it.
private struct WildStandCard: View {

    let patch: PatchSummary
    let chunk: Chunk?
    /// For a stand growing on an empty cell of the garden, which a tap used to
    /// treat as the cell alone, so the stand could never be looked at.
    var plantable: (() -> Void)?
    var onDismiss: () -> Void

    private var workingLine: String {
        "\(patch.foragersWorkingIt.counted("bee")) working it"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(patch.speciesName)
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }

            if let chunk {
                Text(chunk.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.wildInk)
            }

            HStack(spacing: 10) {
                Label(
                    patch.isInBloom ? "In bloom" : "Not in bloom",
                    systemImage: patch.isInBloom ? "sun.max.fill" : "moon.zzz.fill"
                )
                .foregroundStyle(patch.isInBloom ? Theme.wildInk : .secondary)

                Text(workingLine)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if let plantable {
                Button("Plant a Flower Here", systemImage: "camera.fill", action: plantable)
                    .buttonStyle(.bordered)
                    .tint(Theme.honey)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
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
    var onSelectWild: (PatchSummary) -> Void
    var onPhotograph: (HexCoordinate?) -> Void
    @Binding var bloomingCell: HexCoordinate?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A flower blooming where one was just planted, and when it began.
    @State private var bloom: MapLife.Bloom?

    /// Country coming out of the fog, and when it began to.
    @State private var reveals: [MapLife.Reveal] = []

    /// Chunks the player has already seen drawn, kept across launches so that
    /// what the scouts or the foragers found while the app was closed is shown
    /// arriving the next time the map is looked at, not silently already there.
    @AppStorage("seenChunks") private var seenChunksRaw = ""

    /// Haptic triggers.
    @State private var bloomCount = 0
    @State private var revealCount = 0

    /// Where a pan started from, so that a drag is measured from the place the
    /// finger went down rather than accumulated frame by frame.
    @State private var panAnchor: CGPoint?
    /// The same for a pinch: `MagnifyGesture` reports a multiple of the zoom
    /// the gesture began at.
    @State private var zoomAnchor: CGFloat?

    /// True while each gesture is live. Gesture state resets when a gesture
    /// is cancelled as well as when it ends — a sheet, a tab switch, the
    /// scroll view taking the touch — where `onEnded` never runs; the anchors
    /// above used to survive those, and the next drag or pinch snapped back
    /// to where the cancelled one began.
    @GestureState private var isPanning = false
    @GestureState private var isPinching = false
    /// Set when a pinch interrupts a drag, so the drag picks up from where
    /// the pinch left the map rather than from where the finger first went
    /// down.
    @State private var panResumesAfterPinch = false

    /// The box the chunks fill, in units of one hexagon's radius. Everything
    /// else — the frame's shape, the fit, how far the map may be dragged —
    /// comes from this one rectangle.
    ///
    /// Rumoured ground counts towards it. A rumour is drawn, so it has to have
    /// room: leaving it out would put the ring of paper the dancers pointed at
    /// half off the edge of the frame, where it could not be seen and could
    /// not be panned to.
    private var bounds: CGRect {
        MapGeometry.bounds(for: chunks.map(\.coordinate) + terrain.rumoured)
    }

    /// Everything standing wild in a cell the map is drawing, found once per
    /// redraw rather than searched for cell by cell.
    ///
    /// Keyed by cell because that is how both the drawing and the tap ask for
    /// it. A cell holds one patch, so the last writer wins and there is
    /// nothing to reconcile.
    private var wildByCell: [HexCoordinate: PatchSummary] {
        var found: [HexCoordinate: PatchSummary] = [:]
        for patch in snapshot.wildPatches {
            if let cell = patch.cell { found[cell] = patch }
        }
        return found
    }

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
            .overlay {
                MapLife(
                    zoom: layout.zoom,
                    focusX: layout.focus.x,
                    focusY: layout.focus.y,
                    bounds: bounds,
                    flights: reduceMotion ? [] : flights,
                    bloom: reduceMotion ? nil : bloom,
                    reveals: reveals
                )
            }
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
            .onChange(of: isPanning) { _, live in
                if !live {
                    panAnchor = nil
                    panResumesAfterPinch = false
                }
            }
            .onChange(of: isPinching) { _, live in if !live { zoomAnchor = nil } }
            .accessibilityRepresentation { reading }
        }
        .onChange(of: bloomingCell, initial: true) { _, cell in
            guard let cell else { return }
            bloomingCell = nil
            // Only if something was actually planted there.
            guard terrain.garden.contains(where: { $0.cell == cell && $0.patchID != nil }) else { return }
            bloom = MapLife.Bloom(cell: cell, start: .now)
            bloomCount += 1
            Task {
                try? await Task.sleep(for: .seconds(MapLife.bloomDuration))
                if bloom?.cell == cell { bloom = nil }
            }
        }
        .onAppear { revealNewGround() }
        .onChange(of: chunks.map(\.coordinate)) { _, _ in revealNewGround() }
        .sensoryFeedback(.impact(weight: .light), trigger: bloomCount)
        .sensoryFeedback(.success, trigger: revealCount)
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

    // MARK: What moves

    /// Bees on their way to whatever they are working, while they are flying.
    /// A handful per flower rather than one per forager — enough to show
    /// where the colony's effort is going, and which way.
    private var flights: [MapLife.Flight] {
        guard snapshot.isForaging else { return [] }
        return (snapshot.patches + snapshot.wildPatches).compactMap { patch in
            guard patch.foragersWorkingIt > 0, let cell = patch.cell else { return nil }
            return MapLife.Flight(to: cell, bees: min(5, 1 + patch.foragersWorkingIt / 10))
        }
    }

    /// Fades in whatever ground has been found since the map was last seen.
    private func revealNewGround() {
        let current = chunks.map(\.coordinate)
        let key = { (chunk: ChunkCoordinate) in "\(chunk.q),\(chunk.r)" }
        let currentKeys = Set(current.map(key))
        // The first time, everything is simply there: nothing has been found,
        // the map is just being looked at for the first time.
        guard !seenChunksRaw.isEmpty else {
            seenChunksRaw = currentKeys.sorted().joined(separator: ";")
            return
        }
        let seen = Set(seenChunksRaw.split(separator: ";").map(String.init))
        let found = current.filter { !seen.contains(key($0)) }
        // A new colony on new ground is not a discovery either.
        guard !found.isEmpty, found.count < current.count else {
            seenChunksRaw = currentKeys.sorted().joined(separator: ";")
            return
        }
        seenChunksRaw = currentKeys.union(seen).sorted().joined(separator: ";")
        guard !reduceMotion else { return }

        let reveal = MapLife.Reveal(cells: found.flatMap(\.cells), start: .now)
        reveals.append(reveal)
        revealCount += 1
        Task {
            try? await Task.sleep(for: .seconds(MapLife.revealDuration))
            reveals.removeAll { $0.start == reveal.start }
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, layout: MapLayout) {
        // Everything past the known chunks: paper to the edge of the frame.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.fog))

        // Ground the dancers have pointed at, under the ground the bees have
        // actually walked over: paper with an outline on it, and no biome,
        // because the biome is a guess until somebody goes.
        drawRumoured(terrain.rumoured, in: &context, layout: layout)

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

        // What the bees found for themselves. A small upright triangle rather
        // than the garden's round dot, and leaf green rather than pollen
        // gold: a stand of heather nobody photographed must not be mistaken
        // at a glance for a flower the player went out and found. Solid while
        // it is in flower, an outline when it is not, and either way carried
        // at what is left of it — a stripped patch fades towards the ground
        // it stands on without ever quite leaving the map, because it will be
        // back next year and the garden's plantings will not.
        for (cell, patch) in wildByCell {
            let mark = wildMark(in: layout.dot(at: cell, fraction: 0.34))
            let strength = 0.35 + 0.65 * max(0, min(1, patch.remainingFraction))
            if patch.isInBloom {
                context.fill(mark, with: .color(Theme.wild.opacity(strength)))
            } else {
                context.stroke(
                    mark,
                    with: .color(Theme.wild.opacity(strength * 0.8)),
                    lineWidth: max(0.5, layout.radius * 0.1)
                )
            }
        }

        // The nest, at the origin, in honey.
        let nest = layout.path(for: .origin)
        context.fill(nest, with: .color(Theme.honeyFill))
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

    /// The mark a wild stand is drawn as, inside the box a garden dot would
    /// have filled.
    ///
    /// An upright triangle, which is the shape a map has meant "something
    /// growing here that nobody planted" for as long as there have been maps.
    /// Narrower than the box it is given so that, side by side with a garden
    /// dot of the same nominal size, it reads as the smaller mark.
    private func wildMark(in box: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.closeSubpath()
        return path
    }

    /// Country the dancers have pointed at and nobody has walked over.
    ///
    /// Called from the top of `draw(in:size:layout:)`, after the paper and
    /// before the ground, with the same coordinates `bounds` is measured from
    /// — `MapGeometry.bounds(for:)` takes coordinates rather than chunks
    /// precisely so that a rumour, which has no biome and no name to speak of,
    /// can still make room for itself in the frame.
    ///
    /// Section 7 of docs/WORLD.md wants a rumoured chunk to show its outline
    /// and nothing else, and this is that outline.
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
                    with: .color(Theme.rumourLine),
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

        let garden = terrain.garden.first { $0.cell == cell }
        if let garden, let patch = patch(in: garden) {
            onSelectPatch(patch)
            return
        }

        // Something the bees found. Ahead of the chunk, because a stand is the
        // smaller and more particular thing to have aimed at: a player who
        // wanted the parish can tap the ground beside it. Ahead of an empty
        // garden cell too, since the ring can open over a stand, and the card
        // offers the planting.
        if let wild = wildByCell[cell] {
            onSelectWild(wild)
            return
        }

        if let garden {
            onPhotograph(garden.cell)
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
            .updating($isPanning) { _, live, _ in live = true }
            .onChanged { value in
                // A pinch owns the map while it lasts. Both used to write the
                // focus in the same frame, and the pan's arithmetic undid the
                // pinch's anchoring, so a zoom drifted out from under the
                // fingers.
                guard zoomAnchor == nil else {
                    panAnchor = nil
                    panResumesAfterPinch = true
                    return
                }
                // Resuming after a pinch, anchored so the map stays where the
                // pinch left it however far the finger has travelled since it
                // went down; otherwise from the focus, so the map follows the
                // finger from the first point.
                let start = panAnchor ?? (panResumesAfterPinch
                    ? CGPoint(
                        x: layout.focus.x + value.translation.width / layout.radius,
                        y: layout.focus.y + value.translation.height / layout.radius
                    )
                    : layout.focus)
                panAnchor = start
                panResumesAfterPinch = false
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
            .updating($isPinching) { _, live, _ in live = true }
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

            // Everything past the six. Named and placed by biome only, which
            // is all a stretch of country the colony has merely been to is —
            // the six around home get a direction because they are the ones a
            // player can hold in their head.
            ForEach(furtherAfield) { chunk in
                Button {
                    onSelectChunk(chunk)
                } label: {
                    Text("\(chunk.name), \(chunk.biome.displayName.lowercased()), found since.")
                }
            }

            if !terrain.rumoured.isEmpty {
                Text("\(terrain.rumoured.count.counted("stretch", plural: "stretches")) of country the dancers have pointed at and nobody has been to.")
            }

            // One line per stretch of country rather than one per stand:
            // there are hundreds of these and a list of them is not a map. A
            // parish and what is out in it is what a forager would say.
            ForEach(Array(wildInBloom.enumerated()), id: \.offset) { _, chunk in
                Button {
                    onSelectWild(chunk.firstStand)
                } label: {
                    Text("\(chunk.name): \(chunk.species.spokenList) in bloom.")
                }
            }

            ForEach(planted) { cell in
                Button {
                    onSelectPatch(cell.patch)
                } label: {
                    Text(label(for: cell))
                }
            }

            // By ring, so where a flower goes can be chosen here as well: ring
            // 1 is the close one, and worth more than a tap could say.
            ForEach(emptyByRing, id: \.ring) { group in
                Button {
                    onPhotograph(group.first)
                } label: {
                    Text("\(group.count.counted("empty cell")) in ring \(group.ring) of the garden. Photograph a flower to plant one.")
                }
            }
        }
    }

    private var emptyByRing: [(ring: Int, count: Int, first: HexCoordinate)] {
        Dictionary(grouping: terrain.emptyCells, by: \.ring)
            .sorted { $0.key < $1.key }
            .compactMap { ring, cells in
                cells.first.map { (ring, cells.count, $0.cell) }
            }
    }

    /// The six directions, in the order `HexCoordinate.directions` fixes them
    /// — east first, then clockwise with `r` increasing southward.
    private static let compass = [
        "east", "south-east", "south-west", "west", "north-west", "north-east"
    ]

    private func label(for planted: PlantedCell) -> String {
        let metres = Int(planted.garden.distanceMetres)
        let remaining = Int((planted.patch.remainingFraction * 100).rounded())
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

    /// Discovered ground that is not home and not one of the six: what the
    /// foragers and the scouts have added since the colony arrived.
    private var furtherAfield: [Chunk] {
        let first = Set([terrain.home.coordinate] + terrain.neighbours.map(\.coordinate))
        return terrain.discovered.filter { !first.contains($0.coordinate) }
    }

    /// What is in flower out in the country, one line to a parish.
    private struct WildChunk {
        let name: String
        let species: [String]
        /// Where a screen reader goes to hear about them.
        let firstStand: PatchSummary
    }

    private var wildInBloom: [WildChunk] {
        var species: [ChunkCoordinate: Set<String>] = [:]
        var first: [ChunkCoordinate: PatchSummary] = [:]
        for patch in snapshot.wildPatches where patch.isInBloom {
            guard let cell = patch.cell else { continue }
            let chunk = ChunkCoordinate.containing(cell)
            species[chunk, default: []].insert(patch.speciesName)
            if first[chunk] == nil { first[chunk] = patch }
        }

        // Walked in the discovered order so the reading is stable between
        // ticks, and named from the terrain so a stand in ground that has
        // somehow gone unknown is left out rather than given a coordinate.
        return terrain.discovered.compactMap { chunk in
            guard let names = species[chunk.coordinate], !names.isEmpty,
                  let stand = first[chunk.coordinate] else { return nil }
            return WildChunk(name: chunk.name, species: names.sorted(), firstStand: stand)
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

// MARK: - What moves

/// The map's living layer, over the ground: bees flying to and from what they
/// work, a flower blooming where one has just been planted, and country
/// coming out of the fog. Drawn apart from the ground so the ground is not
/// redrawn sixty times a second, and paused whenever nothing is moving.
///
/// Animatable over the camera for the same reason `MapCanvas` is, so a bee
/// stays over its flower while the map glides to the nest.
private struct MapLife: View, Animatable {

    struct Flight {
        let to: HexCoordinate
        let bees: Int
    }

    struct Bloom {
        let cell: HexCoordinate
        let start: Date
    }

    struct Reveal {
        let cells: [HexCoordinate]
        let start: Date
    }

    static let bloomDuration: TimeInterval = 1.6
    static let revealDuration: TimeInterval = 1.8

    var zoom: CGFloat
    var focusX: CGFloat
    var focusY: CGFloat

    let bounds: CGRect
    let flights: [Flight]
    let bloom: Bloom?
    let reveals: [Reveal]

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(zoom, AnimatablePair(focusX, focusY)) }
        set {
            zoom = newValue.first
            focusX = newValue.second.first
            focusY = newValue.second.second
        }
    }

    private var isIdle: Bool { flights.isEmpty && bloom == nil && reveals.isEmpty }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isIdle)) { timeline in
            Canvas { context, size in
                let layout = MapLayout(
                    size: size, bounds: bounds, zoom: zoom,
                    focus: CGPoint(x: focusX, y: focusY)
                )
                let now = timeline.date
                drawReveals(in: &context, layout: layout, now: now)
                drawBloom(in: &context, layout: layout, now: now)
                drawFlights(in: &context, layout: layout, now: now)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func centre(of cell: HexCoordinate, in layout: MapLayout) -> CGPoint {
        let dot = layout.dot(at: cell, fraction: 0.1)
        return CGPoint(x: dot.midX, y: dot.midY)
    }

    /// The fog drawn back over new ground, thinning to nothing.
    private func drawReveals(in context: inout GraphicsContext, layout: MapLayout, now: Date) {
        for reveal in reveals {
            let progress = min(1, max(0, now.timeIntervalSince(reveal.start) / Self.revealDuration))
            let fog = 1 - progress * progress * (3 - 2 * progress)
            guard fog > 0 else { continue }
            for cell in reveal.cells {
                context.fill(layout.path(for: cell), with: .color(Theme.fog.opacity(fog)))
            }
        }
    }

    /// Two rings of honey spreading out from the new flower, and the flower
    /// itself swelling into place under them.
    private func drawBloom(in context: inout GraphicsContext, layout: MapLayout, now: Date) {
        guard let bloom else { return }
        let progress = min(1, max(0, now.timeIntervalSince(bloom.start) / Self.bloomDuration))
        let centre = centre(of: bloom.cell, in: layout)
        for ring in 0..<2 {
            let local = min(1, max(0, progress * 1.4 - Double(ring) * 0.3))
            guard local > 0, local < 1 else { continue }
            let radius = layout.radius * (0.4 + 2.2 * local)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Theme.honeyFill.opacity(1 - local)),
                lineWidth: max(1, layout.radius * 0.18 * (1 - local))
            )
        }
        let swell = sin(min(1, progress * 2) * .pi) * 0.35
        let size = layout.radius * (0.84 + swell)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)),
            with: .color(Theme.pollen.opacity(0.9 * (1 - progress)))
        )
    }

    /// Bees going out and coming back. Each makes the round trip in a time
    /// that grows with the distance, spaced along it so a busy flower has a
    /// little line of them rather than a clump.
    private func drawFlights(in context: inout GraphicsContext, layout: MapLayout, now: Date) {
        let nest = centre(of: .origin, in: layout)
        let beeRadius = max(1.4, layout.radius * 0.13)
        let seconds = now.timeIntervalSinceReferenceDate

        for flight in flights {
            let target = centre(of: flight.to, in: layout)
            let dx = target.x - nest.x, dy = target.y - nest.y
            let length = max(1, hypot(dx, dy))
            // Across the path, for the wander.
            let nx = -dy / length, ny = dx / length
            let period = 2.5 + Double(length / max(layout.radius, 1)) * 0.35

            for bee in 0..<flight.bees {
                let phase = (seconds / period + Double(bee) / Double(flight.bees)
                    + Double(abs(flight.to.q &* 31 &+ flight.to.r)) * 0.137)
                    .truncatingRemainder(dividingBy: 1)
                // Out on the first half of the trip, home on the second.
                let along = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                let wander = sin(phase * .pi * 6 + Double(bee)) * Double(layout.radius) * 0.25
                let point = CGPoint(
                    x: nest.x + dx * along + nx * wander,
                    y: nest.y + dy * along + ny * wander
                )
                let rect = CGRect(
                    x: point.x - beeRadius, y: point.y - beeRadius,
                    width: beeRadius * 2, height: beeRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(Theme.honey))
                context.stroke(
                    Path(ellipseIn: rect), with: .color(Theme.propolis.opacity(0.8)),
                    lineWidth: max(0.5, beeRadius * 0.35)
                )
            }
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
    WorldView(onPhotograph: { _ in }, bloomingCell: .constant(nil))
        .environment(GameStore.preview())
}
