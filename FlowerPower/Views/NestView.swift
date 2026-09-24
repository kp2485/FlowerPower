//
//  NestView.swift
//  FlowerPower
//
//  The inside of the hive, drawn as comb, and meant to be touched.
//
//  Features.md asked for a hex cell per larva and per bee. A real nest reaches
//  several hundred cells, and drawing that many individually addressable views
//  is both slow and unreadable — so the comb is rendered as a single Canvas and
//  laid out in the concentric way a colony actually organises itself: brood in
//  the warm centre, pollen ringed around it, honey banked at the edges.
//
//  That arrangement is not decoration. It is how a beekeeper reads a frame at a
//  glance, and it makes the state of the colony legible without a single label.
//
//  Both halves of that — the arrangement and the geometry — now live in the
//  package, as `CombLayout` and `CombGeometry`. They used to be here, inside
//  the Canvas closure, which meant the one part of the nest a player was about
//  to start putting a finger on was the one part nothing on the development
//  machine could compile, let alone test. What is left in this file is what a
//  view should be: where the touches go and what colour things are.
//
//  A Canvas draws no views, so a cell cannot be tapped in the ordinary way.
//  The finger is turned back into a cell index by `CombGeometry.index(atX:y:)`
//  and the same index drives all three affordances: a long press that sweeps,
//  a tap that opens a sheet for anybody who never discovers the long press, and
//  a VoiceOver adjustable action that steps the highlight through the bands of
//  the comb rather than through six hundred hexagons.
//

import SwiftUI
import TipKit
import FlowerPowerCore
import FlowerPowerGame

struct NestView: View {

    @Environment(GameStore.self) private var store
    @State private var showingJobs = false

    /// A legend entry picked out, dimming everything on the comb that is not
    /// it. Held here rather than in the panel because the legend and the comb
    /// are no longer in the same container — see the body.
    @State private var highlighted: CombCellFamily?

    private var snapshot: ColonySnapshot { store.snapshot }

    /// The comb pinned, and everything else scrolling underneath it.
    ///
    /// The comb used to sit inside the `ScrollView` with the rest, and it
    /// carries a hold-then-drag gesture. On a device a scroll view's own pan
    /// wins a vertical drag that starts inside it — so the sweep would have
    /// worked sideways and scrolled the page the moment a finger moved down
    /// the comb. Rather than argue with that (a high-priority gesture, and
    /// scrolling switched off while a cell is held), the comb is simply not
    /// in a scroll view. It is the page's main content and it fits above the
    /// fold on every phone this runs on, which are held upright: the app is
    /// portrait-only. The legend, the tip and the jobs scroll below it.
    var body: some View {
        // Laid out once here rather than inside `CombPanel`, because the
        // panel re-renders on every gesture event and building six hundred
        // summaries under a moving finger is work nobody asked for. This body
        // runs when the snapshot changes, which is three times a minute at
        // worst.
        let layout = CombLayout(snapshot: snapshot)

        NavigationStack {
            VStack(spacing: 0) {
                CombPanel(snapshot: snapshot, layout: layout, highlighted: highlighted)
                    // Its own height, worked out from the width, exactly as
                    // it was inside the scroll view — which proposes no
                    // height either. Without this the stack would share the
                    // screen out evenly between the comb and the scroll, and
                    // the comb would come out narrower than the page.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        CombLegend(layout: layout, highlighted: $highlighted)
                            .card()
                        TipView(AppTips.nest)
                        JobBreakdown(population: snapshot.population)
                    }
                    .padding([.horizontal, .bottom])
                    .padding(.top, 8)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nest")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Jobs", systemImage: "slider.horizontal.3") {
                        showingJobs = true
                    }
                }
            }
            .sheet(isPresented: $showingJobs) {
                JobAssignmentView()
            }
        }
    }
}

// MARK: - The comb

private struct CombPanel: View {

    let snapshot: ColonySnapshot
    let layout: CombLayout

    /// A legend entry picked out, dimming everything that is not it. Read
    /// here and set by the legend, which lives in the scrolling part of the
    /// page below — so `NestView` holds it and hands this down.
    let highlighted: CombCellFamily?

    /// The cell under the finger during a long press, and the one a VoiceOver
    /// user has stepped to. One piece of state for both, so the highlight and
    /// the spoken value never disagree about where the player is.
    @State private var held: Int?

    /// A cell the player tapped, which stays until it is dismissed.
    @State private var opened: CombCellSummary?

    /// Which band the adjustable action has reached.
    @State private var band = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            comb
        }
        .card()
        .sheet(item: $opened) { cell in
            CombCellSheet(cell: cell)
        }
    }

    private var header: some View {
        HStack {
            SectionTitle("Comb", systemImage: "hexagon.fill")
            Spacer()
            Text(layout.isTruncated
                 ? "\(layout.cellsDrawn) of \(layout.builtCells) cells"
                 : "\(layout.builtCells) cells")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: The comb itself

    private var comb: some View {
        GeometryReader { proxy in
            let geometry = CombGeometry(
                cellCount: layout.cellsDrawn,
                width: Double(proxy.size.width),
                height: Double(proxy.size.height)
            )

            Canvas { context, _ in
                draw(in: &context, geometry: geometry)
            }
            // A Canvas has no shape of its own to be hit, so every touch in
            // the square counts and the geometry decides whether it landed on
            // a cell or in the gutter between two.
            .contentShape(Rectangle())
            .gesture(sweep(over: geometry))
            // The tap is for the player who never discovers the long press.
            // A tap recogniser fails once a long press has succeeded, so this
            // should not fire at the end of a sweep; the guard is there
            // because a sheet opening as a finger lifts would be maddening and
            // costs one comparison to rule out. Written the way the World
            // map's tap is, which has been through the compiler: the
            // location comes in the view's own space by default.
            .onTapGesture { point in
                guard held == nil else { return }
                let index = geometry.index(atX: Double(point.x), y: Double(point.y))
                opened = layout.cell(at: index)
            }
            .overlay {
                callout(over: geometry, in: proxy.size)
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
        // A ceiling that no phone reaches. The comb is no longer in a scroll
        // view, so a comb as tall as a wide screen is wide would have
        // nowhere to go; this keeps it on the screen if the app is ever run
        // somewhere wider than a phone held upright.
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        // Only when the cell under the finger changes, not on every pixel of
        // the sweep: a haptic per pixel is a buzz, not a texture.
        .sensoryFeedback(.selection, trigger: held)
        // A Canvas draws no accessibility children of its own, so there is
        // nothing for a label to attach to. This makes the whole comb one
        // element that reads as a sentence — and adjustable, so it can be
        // stepped through band by band instead of cell by cell.
        .accessibilityElement()
        .accessibilityLabel("Comb")
        .accessibilityValue(accessibilityDescription)
        .accessibilityHint("Swipe up or down to move out through the comb, "
                           + "from the brood nest to the honey.")
        .accessibilityAdjustableAction { direction in
            step(direction)
        }
    }

    private func draw(in context: inout GraphicsContext, geometry: CombGeometry) {
        guard !layout.cells.isEmpty else { return }

        let mortar = Color(.systemBackground).opacity(0.55)
        let mortarWidth = CGFloat(max(0.5, geometry.radius * 0.08))

        for cell in layout.cells {
            let path = hexagon(at: cell.index, geometry: geometry)
            var fill = CombPalette.colour(for: cell.content)

            // Picking a legend entry dims the rest rather than hiding it: the
            // shape of the brood nest is half of what the comb is saying, and
            // blanking it would throw that away to answer a smaller question.
            if let highlighted, cell.family != highlighted {
                fill = fill.opacity(0.18)
            }

            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(mortar), lineWidth: mortarWidth)
        }

        guard let held, layout.cells.indices.contains(held) else { return }
        let path = hexagon(at: held, geometry: geometry)
        // Twice over: a halo of background first so the outline reads against
        // whatever colour the neighbouring cells happen to be, then the
        // outline itself.
        context.stroke(
            path,
            with: .color(Color(.systemBackground)),
            lineWidth: CGFloat(max(2, geometry.radius * 0.5))
        )
        context.stroke(
            path,
            with: .color(.primary),
            lineWidth: CGFloat(max(1, geometry.radius * 0.25))
        )
    }

    private func hexagon(at index: Int, geometry: CombGeometry) -> Path {
        var path = Path()
        for (corner, point) in geometry.corners(of: index).enumerated() {
            let vertex = CGPoint(x: point.x, y: point.y)
            if corner == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Touch

    /// Hold, then sweep. There is no scroll view around the comb any more
    /// (see `NestView`), so nothing else on the page wants this drag; the
    /// long press is kept because it is what tells a sweep from a tap, and a
    /// tap opens the sheet.
    ///
    /// The highlight appears on the first movement after the press rather than
    /// on the press itself, because `SequenceGesture` reports the press
    /// succeeding before it reports where the finger is. In practice a finger
    /// is never perfectly still, so the gap is imperceptible — and the
    /// alternative, a second zero-distance drag recogniser running alongside
    /// the scroll view's own, is a much worse trade.
    private func sweep(over geometry: CombGeometry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value, let drag else { return }
                let index = geometry.index(
                    atX: Double(drag.location.x),
                    y: Double(drag.location.y)
                )
                if index != held { held = index }
            }
            .onEnded { _ in
                held = nil
            }
    }

    @ViewBuilder
    private func callout(over geometry: CombGeometry, in size: CGSize) -> some View {
        if let held, let cell = layout.cell(at: held) {
            let middle = geometry.centre(of: held)
            let canvasWidth = Double(size.width)
            let canvasHeight = Double(size.height)

            // Clamped so the card cannot run off either edge, however near the
            // rim of the comb the finger is.
            let width = min(240, max(150, canvasWidth - 32))
            let leftmost = width / 2 + 8
            let rightmost = max(leftmost, canvasWidth - width / 2 - 8)

            // Above the finger in the lower half of the comb, below it in the
            // upper half, so the hand is never over the words.
            let above = middle.y > canvasHeight / 2
            let y = above
                ? max(52, middle.y - 78)
                : min(max(52, canvasHeight - 52), middle.y + 78)

            CombCallout(cell: cell)
                .frame(width: CGFloat(width))
                .position(
                    x: CGFloat(min(max(middle.x, leftmost), rightmost)),
                    y: CGFloat(y)
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: VoiceOver

    /// Steps the highlight through the bands of the comb.
    ///
    /// Bands rather than cells. A strong colony is six hundred hexagons, and
    /// an accessibility rotor with six hundred stops in it is not a screen
    /// anybody can use; "brood nest, pollen band, honey" is the same reading a
    /// beekeeper takes off a frame at a glance.
    private func step(_ direction: AccessibilityAdjustmentDirection) {
        guard !layout.regions.isEmpty else { return }

        switch direction {
        case .increment: band = min(layout.regions.count - 1, band + 1)
        case .decrement: band = max(0, band - 1)
        @unknown default: return
        }

        held = layout.regions[band].representativeIndex
    }

    private var accessibilityDescription: String {
        let opening = "\(layout.builtCells) cells. "
            + "\(snapshot.population.brood) brood in the centre, "
            + "stores around the edge, "
            + "\(snapshot.nest.freeCells) cells empty."

        guard layout.regions.indices.contains(band) else { return opening }
        let region = layout.regions[band]
        return opening
            + " Band \(band + 1) of \(layout.regions.count): "
            + "\(region.title). \(region.detail)"
    }
}

// MARK: - What is in this one

/// The small card that follows a finger across the comb.
private struct CombCallout: View {

    let cell: CombCellSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(CombPalette.colour(for: cell.content))
                    .frame(width: 9, height: 9)
                Text(cell.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(cell.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

/// The same thing, as a sheet — for the player who taps rather than holds, and
/// for anybody who wants to read it without keeping a thumb on the screen.
private struct CombCellSheet: View {

    let cell: CombCellSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(CombPalette.colour(for: cell.content))
                                .frame(width: 16, height: 16)
                            Text(cell.title)
                                .font(.title3.weight(.semibold))
                        }
                        Text(cell.detail)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Shown only where the colony records it. Drone comb is a
                    // count in the engine, not a map, so a cell of honey has
                    // no known size and this row is simply absent rather than
                    // guessing "worker".
                    if let type = cell.cellType {
                        LabeledContent("Comb", value: type.displayName)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(cell.family.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Colours

/// What colour a cell is drawn in.
///
/// Here rather than in `Theme` because these are families of *cells* — a thing
/// only this screen has — while `Theme` is the vocabulary the phone and the
/// watch share.
private enum CombPalette {

    static func colour(for content: CombCellContent) -> Color {
        if case .queenCell = content { return Theme.queen }
        if let stage = content.stage { return Theme.colour(for: stage) }
        if let resource = content.resource { return Theme.colour(for: resource) }
        return Color(.systemGray5)
    }

    static func colour(for family: CombCellFamily) -> Color {
        switch family {
        case .eggs: return Theme.colour(for: .egg)
        case .larvae: return Theme.colour(for: .larva)
        case .sealedBrood: return Theme.colour(for: .pupa)
        case .beeBread: return Theme.colour(for: .beeBread)
        case .pollen: return Theme.colour(for: .pollen)
        case .nectar: return Theme.colour(for: .nectar)
        case .honey: return Theme.colour(for: .honey)
        case .queenCells: return Theme.queen
        case .empty: return Color(.systemGray5)
        }
    }
}

// MARK: - Legend

/// The legend, which is now a control rather than a key.
///
/// It had nine fixed rows, several of which named something the comb was not
/// showing. It lists what is actually there, with the count, and tapping a
/// row picks those cells out on the comb above — which is the cheapest way to
/// answer "where is the pollen?" that does not involve another screen.
///
/// It is in a card of its own again, the first thing in the scroll under the
/// pinned comb. It was in the comb's card for a round, which put it where the
/// eye already was; but on a small phone the comb and three rows of legend
/// together leave almost nothing below them to scroll, and the legend is the
/// part that can move. It still sits directly under the comb when the page
/// opens.
private struct CombLegend: View {

    let layout: CombLayout
    @Binding var highlighted: CombCellFamily?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
            ForEach(layout.familiesPresent) { family in
                row(family)
            }
        }
    }

    private func row(_ family: CombCellFamily) -> some View {
        let count = layout.count(of: family)
        let isPicked = highlighted == family

        return Button {
            highlighted = isPicked ? nil : family
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(CombPalette.colour(for: family))
                    .frame(width: 11, height: 11)
                Text(family.displayName)
                    .font(.caption2)
                    .foregroundStyle(isPicked ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isPicked ? Theme.honey.opacity(0.25) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(family.displayName), \(count) cells")
        .accessibilityHint(isPicked
                           ? "Showing only these. Double tap to show the whole comb."
                           : "Double tap to pick these out on the comb.")
        .accessibilityAddTraits(isPicked ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

// MARK: - Jobs

private struct JobBreakdown: View {

    let population: PopulationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Who is doing what", systemImage: "person.2.badge.gearshape.fill")

            let jobs = population.jobs
                .sorted { $0.value > $1.value }

            if jobs.isEmpty {
                Text("No adult workers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let maximum = jobs.first?.value ?? 1

                // Each row opens the job rather than only reporting it. The
                // breakdown answered "how many nurses" and nothing else; the
                // question a player actually has at that moment is "what is a
                // nurse", and the package has had the answer to that since
                // `Glossary` went in.
                ForEach(jobs, id: \.key) { job, count in
                    NavigationLink {
                        JobDetail(job: job, count: count)
                    } label: {
                        JobRowLabel(job: job, count: count, maximum: maximum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(job.displayName): \(count) bees")
                    .accessibilityHint("Double tap to read what this work is.")
                }
            }

            Text("A worker's job follows her age. She cleans cells, then nurses, then builds and ripens, then guards, and finally forages until she wears out.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct JobRowLabel: View {

    let job: WorkerJob
    let count: Int
    let maximum: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.symbol(for: job))
                .frame(width: 22)
                .foregroundStyle(Theme.worker)
                .accessibilityHidden(true)
            Text(job.displayName)
                .font(.subheadline)
                .minimumScaleFactor(0.7)
            Spacer()
            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Capsule()
                    .fill(Theme.worker.opacity(0.18))
                    .frame(
                        width: geometry.size.width * Double(count) / Double(max(1, maximum)),
                        height: 3
                    )
                    .offset(y: geometry.size.height)
            }
            .frame(height: 0)
        }
    }
}

/// One job, explained, with the workforce doing it.
///
/// A short page rather than a push into `JobAssignmentView`: that view carries
/// its own `NavigationStack` and is presented as a sheet, and the question a
/// row raises is what the work *is*. The lever is one tap further on, where it
/// belongs.
private struct JobDetail: View {

    let job: WorkerJob
    let count: Int

    @State private var showingJobs = false

    private var term: GlossaryTerm { Glossary.term(for: job) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: Theme.symbol(for: job))
                            .foregroundStyle(Theme.worker)
                            .accessibilityHidden(true)
                        Text("\(count) bees")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    Text(term.definition)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    let range = job.adultAgeRange
                    Text("Worked from day \(range.lowerBound) to day \(range.upperBound - 1) "
                         + "of a worker's adult life.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Button {
                    showingJobs = true
                } label: {
                    Label("Lean the colony toward this", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(job.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingJobs) {
            JobAssignmentView()
        }
    }
}

#Preview {
    NestView()
        .environment(GameStore.preview())
}
