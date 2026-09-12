//
//  NestView.swift
//  FlowerPower
//
//  The inside of the hive, drawn as comb.
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

import SwiftUI
import TipKit
import FlowerPowerCore
import FlowerPowerGame

struct NestView: View {

    @Environment(GameStore.self) private var store
    @State private var showingJobs = false

    private var snapshot: ColonySnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TipView(Tips.nest)
                    CombPanel(snapshot: snapshot)
                    CombLegend()
                    JobBreakdown(population: snapshot.population)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nest")
            .toolbar {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Comb", systemImage: "hexagon.fill")
                Spacer()
                Text("\(snapshot.nest.builtCells) cells")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            CombCanvas(contents: CombLayout.contents(for: snapshot))
                .aspectRatio(1.15, contentMode: .fit)
                .frame(maxWidth: .infinity)
                // A Canvas draws no accessibility children of its own, so
                // there was nothing for the label below to attach to. This
                // makes the whole comb one element that reads as a sentence.
                .accessibilityElement()
                .accessibilityLabel("Comb")
                .accessibilityValue(accessibilityDescription)
        }
        .card()
    }

    private var accessibilityDescription: String {
        let population = snapshot.population
        return """
        \(snapshot.nest.builtCells) cells. \
        \(population.brood) brood in the centre, \
        stores around the edge, \
        \(snapshot.nest.freeCells) cells empty.
        """
    }
}

/// What a single hexagon is showing.
enum CellContent: Equatable {
    case empty
    case brood(DevelopmentStage)
    case stores(ResourceKind)
    case queenCell

    var colour: Color {
        switch self {
        case .empty: return Color(.systemGray5)
        case .brood(let stage): return Theme.colour(for: stage)
        case .stores(let kind): return Theme.colour(for: kind)
        case .queenCell: return Theme.queen
        }
    }
}

/// Turns colony counts into a concentric comb layout.
enum CombLayout {

    /// Cells are ordered from the centre outward, so simply filling the array
    /// in order — brood first, then pollen, then honey — reproduces the real
    /// arrangement of a brood nest.
    static func contents(for snapshot: ColonySnapshot) -> [CellContent] {
        let total = max(1, min(snapshot.nest.builtCells, 900))
        var cells: [CellContent] = []
        cells.reserveCapacity(total)

        // Queen cells hang at the very centre, where they are impossible to miss.
        cells.append(contentsOf: Array(repeating: .queenCell, count: snapshot.nest.queenCells.count))

        let population = snapshot.population
        cells.append(contentsOf: Array(repeating: .brood(.egg), count: population.eggs))
        cells.append(contentsOf: Array(repeating: .brood(.larva), count: population.larvae))
        cells.append(contentsOf: Array(repeating: .brood(.pupa), count: population.pupae))

        // Pollen forms the band immediately outside the brood — the bees keep
        // their protein where the nurses are.
        for kind in [ResourceKind.beeBread, .pollen, .nectar, .honey] {
            let amount = snapshot.stores.resources[kind] ?? 0
            guard amount > 0 else { continue }
            let count = Int((amount / kind.unitsPerCell).rounded(.up))
            cells.append(contentsOf: Array(repeating: .stores(kind), count: count))
        }

        if cells.count < total {
            cells.append(contentsOf: Array(repeating: .empty, count: total - cells.count))
        }

        return Array(cells.prefix(total))
    }
}

/// Draws the comb in one pass. A Canvas rather than hundreds of Views, because
/// a strong colony is several hundred cells and SwiftUI should not be asked to
/// diff that on every tick.
private struct CombCanvas: View {

    let contents: [CellContent]

    var body: some View {
        Canvas { context, size in
            guard !contents.isEmpty else { return }

            let layout = HexGrid(cellCount: contents.count, in: size)

            for (index, content) in contents.enumerated() {
                let centre = layout.centre(of: index)
                let path = layout.hexagonPath(at: centre)

                context.fill(path, with: .color(content.colour))
                context.stroke(
                    path,
                    with: .color(Color(.systemBackground).opacity(0.55)),
                    lineWidth: max(0.5, layout.radius * 0.08)
                )
            }
        }
        .drawingGroup()
    }
}

/// A spiral hex grid: cells wind outward from the centre, which gives the
/// concentric brood-nest arrangement for free.
private struct HexGrid {

    let radius: CGFloat
    private let origin: CGPoint
    private let spacing: CGFloat

    init(cellCount: Int, in size: CGSize) {
        // Rings needed to hold this many cells: 1 + 3r(r+1).
        let rings = max(1, Int((Double(cellCount).squareRoot() / 1.7).rounded(.up)))
        let extent = min(size.width, size.height)
        self.radius = extent / CGFloat(2 * rings + 2) * 0.98
        self.spacing = radius * 1.9
        self.origin = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Ring-by-ring spiral position.
    func centre(of index: Int) -> CGPoint {
        guard index > 0 else { return origin }

        // Which ring, and how far around it.
        var ring = 1
        var consumed = 1
        while consumed + 6 * ring <= index {
            consumed += 6 * ring
            ring += 1
        }
        let positionInRing = index - consumed

        let side = min(5, positionInRing / ring)
        let step = positionInRing % ring

        // Standard axial hex directions. Start at one corner of the ring, walk
        // whole sides to reach the current one, then step along it.
        let directions: [(q: Int, r: Int)] = [
            (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1), (1, 0)
        ]

        var q = directions[4].q * ring
        var r = directions[4].r * ring

        for completedSide in 0..<side {
            q += directions[completedSide].q * ring
            r += directions[completedSide].r * ring
        }

        q += directions[side].q * step
        r += directions[side].r * step

        let x = spacing * (CGFloat(q) + CGFloat(r) / 2)
        let y = spacing * CGFloat(r) * 0.866

        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    func hexagonPath(at centre: CGPoint) -> Path {
        var path = Path()
        for corner in 0..<6 {
            // Flat-top hexagons tile the way comb does.
            let angle = CGFloat(corner) * .pi / 3 + .pi / 6
            let point = CGPoint(
                x: centre.x + radius * cos(angle),
                y: centre.y + radius * sin(angle)
            )
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Legend

private struct CombLegend: View {

    private let entries: [(String, Color)] = [
        ("Eggs", Theme.colour(for: .egg)),
        ("Larvae", Theme.colour(for: .larva)),
        ("Sealed brood", Theme.colour(for: .pupa)),
        ("Bee bread", Theme.colour(for: .beeBread)),
        ("Pollen", Theme.colour(for: .pollen)),
        ("Nectar", Theme.colour(for: .nectar)),
        ("Honey", Theme.colour(for: .honey)),
        ("Queen cell", Theme.queen),
        ("Empty", Color(.systemGray5))
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(entries, id: \.0) { name, colour in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colour)
                        .frame(width: 12, height: 12)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
        .accessibilityHidden(true)
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

                ForEach(jobs, id: \.key) { job, count in
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
                    }
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(job.displayName): \(count) bees")
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

#Preview {
    NestView()
        .environment(GameStore.preview())
}
