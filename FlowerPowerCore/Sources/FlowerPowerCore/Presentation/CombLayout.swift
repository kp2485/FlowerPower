//
//  CombLayout.swift
//  FlowerPowerCore
//
//  The comb, cell by cell, so that a finger can be put on one of them.
//
//  The engine keeps counts, not a cell array: two hundred and forty bees, six
//  hundred units of honey, four hundred and ten drawn cells. The Nest screen
//  has always had to invent an arrangement out of that, and it did — inside a
//  `Canvas` in a file no compiler on the development machine can see. So the
//  one thing the player was about to start touching was the one part of the
//  nest nothing could test.
//
//  This is that arrangement, moved into the package and given words. Two rules
//  shaped it.
//
//  **The arrangement is concentric, because a colony's is.** Brood in the warm
//  middle, the pollen the nurses eat in a band immediately around it, nectar
//  and honey banked outside that, and drawn-but-empty comb at the edge. That is
//  how a beekeeper reads a frame at a glance, and it makes the state of the
//  colony legible without a single label.
//
//  **Nothing is invented.** Where the engine knows a cell — and for brood it
//  does, because a larva *is* a cell — the summary says exactly what is in it
//  and how long it has left. Where the engine has only a total, the cell's
//  detail is the total's, phrased as one. A comb that made up a plausible
//  number of days for each of four hundred honey cells would be lying four
//  hundred times, and the player would have no way of knowing which of the
//  numbers on this screen were real.
//

import Foundation

// MARK: - What is in a cell

/// The families the comb is read in: the nine things a cell can be showing.
///
/// Coarser than `CombCellContent`, and that is its job — it is what the legend
/// lists, what a highlight selects, and what the accessibility regions are
/// named after. `CaseIterable` so those all iterate in one fixed order rather
/// than in whatever order a dictionary hands them out.
public enum CombCellFamily: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case eggs
    case larvae
    case sealedBrood
    case beeBread
    case pollen
    case nectar
    case honey
    case queenCells
    case empty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .eggs: return "Eggs"
        case .larvae: return "Larvae"
        case .sealedBrood: return "Sealed brood"
        case .beeBread: return "Bee bread"
        case .pollen: return "Pollen"
        case .nectar: return "Nectar"
        case .honey: return "Honey"
        case .queenCells: return "Queen cells"
        case .empty: return "Empty"
        }
    }

    /// SF Symbol for a legend row. Kept here rather than in `Symbols.swift`
    /// because these are families of *cells*, not engine types, and
    /// `SymbolTests` should go on meaning what it means.
    public var symbolName: String {
        switch self {
        case .eggs: return "circle.dotted"
        case .larvae: return "circle.circle"
        case .sealedBrood: return "circle.fill"
        case .beeBread: return "square.grid.3x3.fill"
        case .pollen: return "circle.grid.2x2.fill"
        case .nectar: return "drop.fill"
        case .honey: return "drop.circle.fill"
        case .queenCells: return "crown.fill"
        case .empty: return "hexagon"
        }
    }

    /// The word for one cell of this kind, for a spoken sentence.
    public var singularName: String {
        switch self {
        case .eggs: return "egg"
        case .larvae: return "larva"
        case .sealedBrood: return "sealed brood cell"
        case .beeBread: return "bee bread cell"
        case .pollen: return "pollen cell"
        case .nectar: return "nectar cell"
        case .honey: return "honey cell"
        case .queenCells: return "queen cell"
        case .empty: return "empty cell"
        }
    }
}

/// What one hexagon is showing, with everything the engine actually knows
/// about it.
public enum CombCellContent: Equatable, Hashable, Sendable {

    /// Drawn, polished and holding nothing.
    case empty

    case egg(BeeKind)

    /// An open larva, with her age and how long before the cell is capped.
    case larva(BeeKind, daysOld: Int, daysToCapping: Int)

    /// Sealed brood, with how long before she chews her way out.
    case cappedBrood(BeeKind, daysToEmergence: Int)

    /// Stored forage or the food made from it. The engine holds these as a
    /// quantity rather than as cells, so a cell of honey is a share of the
    /// hive's honey and says so.
    case stores(ResourceKind)

    case queenCell(QueenCell.Purpose, daysToEmergence: Int)

    public var family: CombCellFamily {
        switch self {
        case .empty: return .empty
        case .egg: return .eggs
        case .larva: return .larvae
        case .cappedBrood: return .sealedBrood
        case .queenCell: return .queenCells
        case .stores(let kind):
            switch kind {
            case .beeBread: return .beeBread
            case .pollen: return .pollen
            case .nectar: return .nectar
            // Honey is the family the rest belong to for drawing purposes:
            // royal jelly, wax, water and propolis never occupy comb, so no
            // cell is ever built from them and this branch is unreachable.
            default: return .honey
            }
        }
    }

    /// The development stage, for anything drawn in brood colours.
    public var stage: DevelopmentStage? {
        switch self {
        case .egg: return .egg
        case .larva: return .larva
        case .cappedBrood: return .pupa
        default: return nil
        }
    }

    public var resource: ResourceKind? {
        if case .stores(let kind) = self { return kind }
        return nil
    }

    public var isBrood: Bool { stage != nil }
    public var isEmpty: Bool { self == .empty }
}

// MARK: - One cell

/// One hexagon of the drawn comb.
public struct CombCellSummary: Identifiable, Equatable, Sendable {

    /// Position in the ring spiral, counting outward from the middle. The
    /// interface turns this into a point with `CombGeometry`.
    public let index: Int

    /// Worker comb, drone comb or a queen cup — where the colony records it.
    ///
    /// Nil is the honest answer for most of the nest. `Comb` keeps a count of
    /// drone cells, not a map of them, so the only cells whose size is known
    /// are the ones with a drone or a queen developing in them. Making the
    /// rest "worker" would have been a guess printed as a fact.
    public let cellType: CellType?

    public let content: CombCellContent

    /// One line: what this is.
    public let title: String

    /// One or two sentences: what the bees are doing with it, and why it
    /// matters.
    public let detail: String

    public var id: Int { index }
    public var family: CombCellFamily { content.family }
}

// MARK: - A band of the comb

/// A contiguous stretch of the comb doing one job — the brood nest, the pollen
/// band, the honey.
///
/// This is what VoiceOver steps through. A comb of six hundred cells is six
/// hundred accessibility elements, which is not a screen anybody can use; four
/// or five bands is the same information at the altitude the eye reads it at.
public struct CombRegion: Identifiable, Equatable, Sendable {

    public let family: CombCellFamily
    public let firstIndex: Int
    public let cellCount: Int
    public let title: String
    public let detail: String

    public var id: Int { firstIndex }

    /// A cell in the middle of the band, for a highlight to settle on.
    public var representativeIndex: Int { firstIndex + cellCount / 2 }
}

// MARK: - The layout

/// The comb, laid out.
public struct CombLayout: Equatable, Sendable {

    /// Every hexagon drawn, from the middle outward.
    public let cells: [CombCellSummary]

    /// The bands, in the order they are laid down.
    public let regions: [CombRegion]

    /// How many cells the colony has actually drawn.
    public let builtCells: Int

    /// How many of them are shown. Fewer than `builtCells` for a very large
    /// nest — see `maximumCellsDrawn`.
    public var cellsDrawn: Int { cells.count }

    public var isTruncated: Bool { cells.count < builtCells }

    /// Ceiling on the number of hexagons. A thousand hexagons on a four-inch
    /// canvas is a texture rather than a comb, and nothing below three pixels
    /// across can be put a finger on.
    public static let maximumCellsDrawn = 900

    /// How many cells of each family are drawn.
    public let counts: [CombCellFamily: Int]

    public func count(of family: CombCellFamily) -> Int { counts[family] ?? 0 }

    /// Every drawn cell of one family, in spiral order. What a legend row
    /// highlights.
    public func indices(of family: CombCellFamily) -> [Int] {
        cells.compactMap { $0.family == family ? $0.index : nil }
    }

    /// The cell at an index, or nil for one off the end — so a hit test that
    /// found nothing and a hit test that found a gap between hexagons can be
    /// handled the same way.
    public func cell(at index: Int?) -> CombCellSummary? {
        guard let index, cells.indices.contains(index) else { return nil }
        return cells[index]
    }

    /// The families present, in `CombCellFamily` order — the legend, with
    /// nothing in it the comb is not showing.
    public var familiesPresent: [CombCellFamily] {
        CombCellFamily.allCases.filter { count(of: $0) > 0 }
    }

    // MARK: Building

    /// Lays the colony out as comb.
    ///
    /// Filled from the middle outward in one pass, which is what makes the
    /// arrangement concentric: queen cells, then brood youngest first, then the
    /// protein the nurses want within reach of it, then the nectar and honey,
    /// then whatever is left over empty. No randomness anywhere — the same
    /// snapshot gives the same comb, because a comb that reshuffled itself
    /// every twenty seconds could not be touched.
    public init(snapshot: ColonySnapshot) {
        let nest = snapshot.nest
        let stores = snapshot.stores.resources

        var contents: [CombCellContent] = []
        var types: [CellType?] = []

        func append(_ content: CombCellContent, _ type: CellType?, times count: Int = 1) {
            guard count > 0 else { return }
            for _ in 0..<count {
                contents.append(content)
                types.append(type)
            }
        }

        // Queen cells hang at the very centre, where they are impossible to
        // miss. A real swarm cell hangs off the bottom edge of the comb, but
        // this is a plan view of a nest rather than a frame held up to the
        // light, and the thing that matters about a queen cell is that the
        // player sees it.
        for cell in nest.queenCellProgress {
            append(
                .queenCell(cell.purpose, daysToEmergence: cell.daysToEmergence),
                .queenCup
            )
        }
        // A snapshot from before queen-cell ages were carried still has the
        // purposes, so draw from those rather than showing nothing.
        if nest.queenCellProgress.isEmpty {
            for purpose in nest.queenCells {
                append(.queenCell(purpose, daysToEmergence: QueenCell.daysToEmergence), .queenCup)
            }
        }

        let queenCellCount = contents.count

        // Brood, youngest at the centre. That is the real arrangement: the
        // queen works outward from the middle of the nest, so the eggs are
        // where she is now and the sealed brood is where she was a fortnight
        // ago.
        for stage in [DevelopmentStage.egg, .larva, .pupa] {
            for brood in nest.brood where brood.stage == stage {
                let type: CellType? = brood.kind == .drone ? .drone
                    : brood.kind == .worker ? .worker : .queenCup
                switch stage {
                case .egg:
                    append(.egg(brood.kind), type)
                case .larva:
                    append(
                        .larva(
                            brood.kind,
                            daysOld: brood.daysInStage,
                            daysToCapping: brood.daysRemainingInStage
                        ),
                        type
                    )
                default:
                    append(
                        .cappedBrood(brood.kind, daysToEmergence: brood.daysToEmergence),
                        type
                    )
                }
            }
        }

        // The protein first, because the bees keep it where the nurses are,
        // then the nectar and the honey banked outside it.
        for kind in [ResourceKind.beeBread, .pollen, .nectar, .honey] {
            let amount = stores[kind] ?? 0
            guard amount > 0, kind.unitsPerCell.isFinite, kind.unitsPerCell > 0 else { continue }
            append(.stores(kind), nil, times: Int((amount / kind.unitsPerCell).rounded(.up)))
        }

        // Queen cells are extra construction rather than drawn cells, so the
        // comb is at least large enough to hold them.
        let total = min(
            max(max(0, nest.builtCells), queenCellCount),
            Self.maximumCellsDrawn
        )

        if contents.count < total {
            append(.empty, nil, times: total - contents.count)
        }
        if contents.count > total {
            contents.removeLast(contents.count - total)
            types.removeLast(types.count - total)
        }

        // Aggregates the detail lines need: a cell of honey cannot say how
        // much honey is in it without knowing how much honey there is.
        var tallies: [CombCellFamily: Int] = [:]
        for content in contents { tallies[content.family, default: 0] += 1 }

        self.cells = contents.indices.map { index in
            CombCellSummary(
                index: index,
                cellType: types[index],
                content: contents[index],
                title: CombLayout.title(for: contents[index]),
                detail: CombLayout.detail(
                    for: contents[index],
                    snapshot: snapshot,
                    tallies: tallies
                )
            )
        }
        self.counts = tallies
        self.builtCells = nest.builtCells
        self.regions = CombLayout.regions(for: contents, snapshot: snapshot)
    }

    // MARK: Words

    static func title(for content: CombCellContent) -> String {
        switch content {
        case .empty:
            return "Empty Cell"
        case .egg(let kind):
            return kind == .drone ? "Drone Egg" : "Egg"
        case .larva(let kind, let daysOld, _):
            let name = kind == .drone ? "Drone Larva" : "Larva"
            return daysOld <= 0 ? "\(name), Just Hatched" : "\(name), Day \(daysOld)"
        case .cappedBrood(let kind, _):
            return kind == .drone ? "Capped Drone Brood" : "Sealed Brood"
        case .stores(let kind):
            switch kind {
            case .nectar: return "Ripening Nectar"
            case .honey: return "Capped Honey"
            case .pollen: return "Pollen"
            case .beeBread: return "Bee Bread"
            default: return kind.displayName
            }
        case .queenCell(let purpose, _):
            return purpose.displayName
        }
    }

    static func detail(
        for content: CombCellContent,
        snapshot: ColonySnapshot,
        tallies: [CombCellFamily: Int]
    ) -> String {
        switch content {

        case .empty:
            let free = snapshot.nest.freeCells
            return "Drawn, polished and waiting. Empty cells are the colony's "
                + "room to move — somewhere for the queen to lay, or somewhere "
                + "to put tonight's nectar — and there are \(free) of them left."

        case .egg(let kind):
            if kind == .drone {
                return "An unfertilised egg, so it carries only the queen's own "
                    + "genes and will be a drone. It hatches in about three days."
            }
            return "Standing on end at the bottom of a cell a cleaner polished "
                + "first. It hatches in about three days, and for those three "
                + "days it is still something the colony could raise a queen from."

        case .larva(let kind, _, let daysToCapping):
            let capping = Self.inDays(daysToCapping, verb: "Capped")
            if kind == .drone {
                return "A drone larva, fed longer and in a wider cell than his "
                    + "sisters. \(capping) — and varroa prefer drone brood, "
                    + "which is where an infestation builds first."
            }
            return "Curled in a pool of brood food and fed something like a "
                + "thousand times a day by the nurses. \(capping)."

        case .cappedBrood(let kind, let daysToEmergence):
            if kind == .drone {
                let emerging = Self.inDays(daysToEmergence, verb: "He emerges")
                return "Sealed under a domed cap while he remakes himself. "
                    + "\(emerging), to eat and wait for a queen to fly."
            }
            let emerging = Self.inDays(daysToEmergence, verb: "She emerges")
            return "Sealed under a wax cap while she remakes herself entirely. "
                + "\(emerging) — and mites breed only inside capped cells, so "
                + "this is where an infestation lives."

        case .stores(let kind):
            let amount = snapshot.stores.resources[kind] ?? 0
            let cells = tallies[content.family] ?? 0
            let share = Self.share(of: amount, across: cells, kind: kind)
            switch kind {
            case .nectar:
                return "Thin nectar, most of it still water, spread shallow so "
                    + "the fanners can drive it down to honey. Left as it is, it "
                    + "ferments. \(share)"
            case .honey:
                return "Ripened to about a fifth water and sealed under wax, "
                    + "where it keeps indefinitely. This is what the colony "
                    + "spends its winter out of. \(share)"
            case .pollen:
                return "Combed off a forager's legs and rammed down into the "
                    + "cell. It is the colony's only protein, and no amount of "
                    + "honey substitutes for it. \(share)"
            case .beeBread:
                return "Pollen packed under a film of honey and left to ferment. "
                    + "This, rather than raw pollen, is what a nurse actually "
                    + "eats. \(share)"
            default:
                return "\(kind.displayName) in the comb. \(share)"
            }

        case .queenCell(let purpose, let daysToEmergence):
            let emerging = Self.inDays(daysToEmergence, verb: "She emerges")
            switch purpose {
            case .swarm:
                return "A queen raised because the colony means to divide. "
                    + "\(emerging) — but the old queen leaves with half the bees "
                    + "before she does, which is what makes this a warning rather "
                    + "than a report."
            case .supersedure:
                return "A daughter raised quietly to replace a failing queen, "
                    + "with no division and no swarm. \(emerging)."
            case .emergency:
                return "Raised in a hurry from an ordinary worker larva after the "
                    + "queen was lost. \(emerging), and she will be a poorer "
                    + "queen for having started late."
            }
        }
    }

    /// "Capped tomorrow", "She emerges in 8 days" — the same shape whichever
    /// end of the sentence it is at.
    static func inDays(_ days: Int, verb: String) -> String {
        switch days {
        case ..<1: return "\(verb) today"
        case 1: return "\(verb) tomorrow"
        default: return "\(verb) in \(days) days"
        }
    }

    /// What one cell's worth of a stored resource is, said as a share of the
    /// whole rather than as a per-cell measurement the engine does not have.
    static func share(of amount: Double, across cells: Int, kind: ResourceKind) -> String {
        guard cells > 0 else { return "" }
        let total = Int(amount.rounded())
        return cells == 1
            ? "The nest holds \(total) units of it, all in this cell."
            : "The nest holds \(total) units across \(cells) cells; the colony "
                + "keeps a total, not a ledger per cell."
    }

    // MARK: Bands

    /// Groups the laid-out cells into the contiguous bands VoiceOver steps
    /// through. Contiguous because the fill order above put them that way.
    static func regions(
        for contents: [CombCellContent],
        snapshot: ColonySnapshot
    ) -> [CombRegion] {
        var regions: [CombRegion] = []
        var start = 0

        while start < contents.count {
            let family = contents[start].family
            var end = start
            while end < contents.count, contents[end].family == family { end += 1 }
            let count = end - start

            regions.append(CombRegion(
                family: family,
                firstIndex: start,
                cellCount: count,
                title: "\(family.displayName), \(count) cells",
                detail: regionDetail(family: family, count: count, snapshot: snapshot)
            ))
            start = end
        }

        return regions
    }

    static func regionDetail(
        family: CombCellFamily,
        count: Int,
        snapshot: ColonySnapshot
    ) -> String {
        switch family {
        case .queenCells:
            return "At the centre of the comb. The colony is rearing a queen."
        case .eggs:
            return "The middle of the brood nest, where the queen is laying now."
        case .larvae:
            return "Open brood, ringed around the eggs and eating hard."
        case .sealedBrood:
            return "Capped brood at the edge of the nest — three weeks of the "
                + "colony's future, already paid for."
        case .beeBread, .pollen:
            return "The band of protein the nurses feed out of, kept within "
                + "reach of the brood."
        case .nectar:
            return "Nectar coming in, spread thin while the fanners ripen it."
        case .honey:
            return "The honey arch, banked over and around the brood. "
                + String(
                    format: "%.0f units of edible stores against the %.0f "
                        + "needed to see the winter out.",
                    snapshot.stores.edibleEnergy,
                    snapshot.stores.winterRequirement
                )
        case .empty:
            return "Drawn comb with nothing in it: the colony's room to grow."
        }
    }
}

// MARK: - Where the hexagons go

/// The spiral of hexagons the comb is drawn on, and the way back from a touch
/// to a cell.
///
/// Pure `Double` arithmetic with no `CGPoint` anywhere in it, so it builds and
/// is tested on the machine with no Mac in it. The interface multiplies by
/// nothing and converts at the last moment.
///
/// The spiral itself is `HexCoordinate.cells(withinRadius:)` — the same ring
/// walk the garden is planted in. There is one implementation of hex geometry
/// in this package and this is not a second one.
public struct CombGeometry: Equatable, Sendable {

    /// Circumradius of one hexagon, in points.
    public let radius: Double

    /// Middle of the canvas.
    public let originX: Double
    public let originY: Double

    /// Distance between neighbouring centres.
    ///
    /// Hexagons tile at `sqrt(3)` times the circumradius. This is wider, which
    /// leaves a hairline of background between cells — comb reads better with
    /// the cells separated, and a hit test that lands in one of those gaps is
    /// a deliberate miss rather than a cell chosen by a rounding error.
    public static let spacingFactor = 1.9

    /// Vertical squash of the axial lattice: cos(30°).
    static let rowHeight = 0.866_025_403_784_438_6

    private let cells: [HexCoordinate]
    private let indexByCell: [HexCoordinate: Int]

    public var cellCount: Int { cells.count }

    /// Rings needed to hold `cellCount` cells, given `1 + 3r(r + 1)` per ring.
    public static func rings(forCellCount cellCount: Int) -> Int {
        var rings = 0
        while 1 + 3 * rings * (rings + 1) < cellCount { rings += 1 }
        return rings
    }

    public init(cellCount: Int, width: Double, height: Double) {
        let wanted = max(0, cellCount)
        let rings = Self.rings(forCellCount: wanted)
        let spiral = HexCoordinate.origin.cells(withinRadius: rings)

        self.cells = Array(spiral.prefix(wanted))

        var index: [HexCoordinate: Int] = [:]
        index.reserveCapacity(self.cells.count)
        for (position, cell) in self.cells.enumerated() { index[cell] = position }
        self.indexByCell = index

        // Fit the whole spiral, both ways. The outermost ring reaches
        // `rings * spacing` sideways and `rings * spacing * rowHeight` up and
        // down, plus one hexagon's own radius at the edge.
        let reach = Self.spacingFactor * Double(rings)
        let horizontal = (width / 2) / (reach + 1)
        let vertical = (height / 2) / (reach * Self.rowHeight + 1)

        self.radius = max(0.1, min(horizontal, vertical))
        self.originX = width / 2
        self.originY = height / 2
    }

    public var spacing: Double { radius * Self.spacingFactor }

    /// Where a cell's middle sits on the canvas.
    public func centre(of index: Int) -> (x: Double, y: Double) {
        guard cells.indices.contains(index) else { return (originX, originY) }
        let cell = cells[index]
        let x = spacing * (Double(cell.q) + Double(cell.r) / 2)
        let y = spacing * Double(cell.r) * Self.rowHeight
        return (originX + x, originY + y)
    }

    /// The six corners of a cell, clockwise from the upper right.
    ///
    /// Pointy-top hexagons, which is how comb is built and how the garden and
    /// the world map are drawn.
    public func corners(of index: Int) -> [(x: Double, y: Double)] {
        let middle = centre(of: index)
        return (0..<6).map { corner in
            let angle = Double(corner) * Double.pi / 3 + Double.pi / 6
            return (middle.x + radius * cos(angle), middle.y + radius * sin(angle))
        }
    }

    /// Which cell a touch landed on, or nil for the background and the gaps
    /// between hexagons.
    ///
    /// The point is turned back into fractional axial coordinates, rounded to
    /// the nearest lattice point in cube space — rounding `q` and `r`
    /// independently picks the wrong cell along a third of every boundary —
    /// and then checked against that cell's actual middle, so a finger in the
    /// gutter between two cells chooses neither.
    public func index(atX x: Double, y: Double) -> Int? {
        guard spacing > 0 else { return nil }

        let localX = x - originX
        let localY = y - originY

        let r = localY / (spacing * Self.rowHeight)
        let q = localX / spacing - r / 2

        guard let cell = Self.round(q: q, r: r), let index = indexByCell[cell] else {
            return nil
        }

        let middle = centre(of: index)
        let dx = x - middle.x
        let dy = y - middle.y
        return (dx * dx + dy * dy).squareRoot() <= radius ? index : nil
    }

    /// Cube rounding: round all three coordinates, then fix up whichever one
    /// moved furthest so that they still sum to zero.
    static func round(q: Double, r: Double) -> HexCoordinate? {
        let s = -q - r
        guard q.isFinite, r.isFinite, s.isFinite else { return nil }

        var roundedQ = q.rounded()
        var roundedR = r.rounded()
        let roundedS = s.rounded()

        let deltaQ = abs(roundedQ - q)
        let deltaR = abs(roundedR - r)
        let deltaS = abs(roundedS - s)

        if deltaQ > deltaR && deltaQ > deltaS {
            roundedQ = -roundedR - roundedS
        } else if deltaR > deltaS {
            roundedR = -roundedQ - roundedS
        }

        guard roundedQ.magnitude < 1e6, roundedR.magnitude < 1e6 else { return nil }
        return HexCoordinate(q: Int(roundedQ), r: Int(roundedR))
    }
}
