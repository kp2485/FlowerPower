//
//  Hex.swift
//  FlowerPowerCore
//
//  The ground the colony lives on: a hexagonal grid of cells two hundred
//  metres across, and a coarser lattice of chunks laid over it.
//
//  Hexagons rather than squares for two reasons. A hex has six neighbours all
//  at the same distance, so straight-line distance is honest in every
//  direction — a square grid lies about its diagonals, and distance is the
//  number that goes straight into `FlowerPatch.distanceMetres` and prices
//  every foraging trip. And it is the shape of the comb, which is not nothing.
//
//  Everything here is pure integer arithmetic. No Apple framework, no
//  `Hasher`-ordered iteration, no floating point in any ordering decision: a
//  cell's neighbours come back in the same order on the phone, on the watch,
//  and in `beesim` on Windows, because a great deal downstream — the garden's
//  planting order, the generator's walk — depends on that.
//

/// A cell of the world, in axial coordinates.
///
/// Axial rather than cube: two numbers instead of three, with the third
/// implied by `q + r + s == 0`. `s` is derived below where the distance
/// formula wants it.
///
/// The origin is the nest. Everything else is measured from there.
public struct HexCoordinate: Codable, Hashable, Equatable, Sendable, Comparable {

    public let q: Int
    public let r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    /// The implied third cube coordinate.
    public var s: Int { -q - r }

    /// Where the nest stands. Every distance in the game is measured from it.
    public static let origin = HexCoordinate(q: 0, r: 0)

    /// How wide a cell is, in metres.
    ///
    /// Two hundred metres is a bee's minute in the air and about the width of
    /// a field, and it is small enough that the first ring of the garden — six
    /// cells around the nest — is all within 200 m, where a patch's distance
    /// efficiency is 0.89 rather than the 0.67 every flower has sat at until
    /// now.
    public static let cellMetres: Double = 200

    // MARK: - Order

    /// A total order, so anything that needs a deterministic sequence of cells
    /// can simply sort.
    ///
    /// By `r` and then `q` — reading order, row by row. The particular order
    /// matters less than that there is one: a `Set<HexCoordinate>` iterated
    /// for output would come out in `Hasher` order, which is randomised once
    /// per process and is exactly the bug `PLAN.md` section 4 opens with.
    public static func < (lhs: HexCoordinate, rhs: HexCoordinate) -> Bool {
        lhs.r == rhs.r ? lhs.q < rhs.q : lhs.r < rhs.r
    }

    // MARK: - Arithmetic

    public static func + (lhs: HexCoordinate, rhs: HexCoordinate) -> HexCoordinate {
        HexCoordinate(q: lhs.q + rhs.q, r: lhs.r + rhs.r)
    }

    public static func - (lhs: HexCoordinate, rhs: HexCoordinate) -> HexCoordinate {
        HexCoordinate(q: lhs.q - rhs.q, r: lhs.r - rhs.r)
    }

    public func scaled(by factor: Int) -> HexCoordinate {
        HexCoordinate(q: q * factor, r: r * factor)
    }

    /// Cells between here and there, counted as a bee flies.
    public func distance(to other: HexCoordinate) -> Int {
        let dq = q - other.q
        let dr = r - other.r
        return (abs(dq) + abs(dr) + abs(dq + dr)) / 2
    }

    /// The same distance in metres, which is what the foraging economics are
    /// priced in. Hex distance times the cell width, and nothing else.
    public func metres(to other: HexCoordinate) -> Double {
        Double(distance(to: other)) * Self.cellMetres
    }

    /// How far this cell is from the nest.
    public var metresFromOrigin: Double { HexCoordinate.origin.metres(to: self) }

    // MARK: - Neighbours and rings

    /// The six steps to a neighbouring cell, in a fixed clockwise order
    /// starting due east.
    ///
    /// With `r` increasing southward this reads east, south-east, south-west,
    /// west, north-west, north-east. Fixed once and never reordered: the
    /// garden plants into ring order, so changing this would move every
    /// flower a player has planted.
    public static let directions: [HexCoordinate] = [
        HexCoordinate(q: 1, r: 0),
        HexCoordinate(q: 0, r: 1),
        HexCoordinate(q: -1, r: 1),
        HexCoordinate(q: -1, r: 0),
        HexCoordinate(q: 0, r: -1),
        HexCoordinate(q: 1, r: -1)
    ]

    /// The six cells touching this one, in `directions` order.
    public var neighbours: [HexCoordinate] {
        Self.directions.map { self + $0 }
    }

    /// What each of the six steps is called, in `directions` order.
    ///
    /// With `r` increasing southward: east, south-east, south-west, west,
    /// north-west, north-east. The same list the garden is planted in, read
    /// aloud — which is what makes "Heather is out on Heather Bank, to the
    /// north-east" a fact about the map rather than a decoration.
    public static let compassNames: [String] = [
        "east", "south-east", "south-west", "west", "north-west", "north-east"
    ]

    /// Which way another cell lies, as a word.
    ///
    /// Nil for the cell itself, which has no direction from itself.
    ///
    /// Six directions rather than eight, because the lattice has six. The
    /// answer is whichever of `directions` the offset points most nearly
    /// along, measured in the plane the hexagons actually sit in — axial
    /// coordinates are skewed, so comparing `q` and `r` directly would call
    /// the same bearing two different things depending on which way it ran.
    /// Ties go to the earlier direction, so the walk order decides and nothing
    /// else can.
    public func direction(to other: HexCoordinate) -> String? {
        let offset = other - self
        guard offset != HexCoordinate(q: 0, r: 0) else { return nil }

        // Pointy-top hexagons: a step in `r` moves down and half a cell right.
        func plane(_ cell: HexCoordinate) -> (x: Double, y: Double) {
            (x: Double(cell.q) + Double(cell.r) * 0.5,
             y: Double(cell.r) * 0.866_025_403_784_438_6)
        }

        let target = plane(offset)
        let length = (target.x * target.x + target.y * target.y).squareRoot()
        guard length > 0 else { return nil }

        var best = 0
        var bestDot = -Double.infinity
        for (index, step) in Self.directions.enumerated() {
            let candidate = plane(step)
            let dot = (target.x * candidate.x + target.y * candidate.y) / length
            if dot > bestDot {
                bestDot = dot
                best = index
            }
        }
        return Self.compassNames[best]
    }

    /// The cells at exactly `radius` from this one, clockwise from the
    /// eastmost.
    ///
    /// Radius 0 is the cell itself; a negative radius is empty rather than an
    /// error, because the callers that walk outward from the nest are happier
    /// with an empty ring than with a precondition.
    ///
    /// The walk is the standard one: start at the eastern corner and follow
    /// each side of the hexagon in turn. From the corner in direction `i` the
    /// side toward corner `i + 1` runs in direction `i + 2`, which is the only
    /// part of this worth checking twice.
    public func ring(radius: Int) -> [HexCoordinate] {
        guard radius > 0 else { return radius == 0 ? [self] : [] }

        var cells: [HexCoordinate] = []
        cells.reserveCapacity(radius * 6)

        var cell = self + Self.directions[0].scaled(by: radius)
        for side in 0..<6 {
            let step = Self.directions[(side + 2) % 6]
            for _ in 0..<radius {
                cells.append(cell)
                cell = cell + step
            }
        }
        return cells
    }

    /// Every cell within `radius`, innermost ring first and clockwise within
    /// each ring. The order the garden is planted in.
    public func cells(withinRadius radius: Int) -> [HexCoordinate] {
        guard radius >= 0 else { return [] }
        return (0...radius).flatMap { ring(radius: $0) }
    }
}

// MARK: - Chunks

/// A stretch of country: a hexagon of 37 cells, three deep around a centre.
///
/// About 1.4 km across, roughly a parish. This is the unit that is generated,
/// discovered and named; the player never sees the word "chunk", only a name
/// the generator gives the ground.
///
/// Chunk coordinates are themselves axial, because the centres of the chunks
/// form a hexagonal lattice of their own. That is the whole trick of tiling
/// hexagons with hexagons: the lattice generated by `(2N+1, -N)` and
/// `(N, N+1)` — here `(7, -3)` and `(3, 4)` — has index `3N² + 3N + 1 = 37`,
/// exactly the number of cells in a chunk, and its points sit `2N + 1 = 7`
/// cells apart, which is more than twice the chunk radius. So the radius-3
/// hexagons around those points neither overlap nor leave a gap, and every
/// cell belongs to exactly one chunk. `HexTests` asserts that directly rather
/// than taking the arithmetic on trust.
public struct ChunkCoordinate: Codable, Hashable, Equatable, Sendable, Comparable {

    public let q: Int
    public let r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    public static let origin = ChunkCoordinate(q: 0, r: 0)

    /// How deep a chunk is around its centre cell.
    public static let radius = 3

    /// Cells in a chunk: `3r² + 3r + 1`.
    public static let cellCount = 3 * radius * radius + 3 * radius + 1

    /// The first lattice vector, in cells. See the note above.
    private static let basisQ = HexCoordinate(q: 2 * radius + 1, r: -radius)
    /// The second.
    private static let basisR = HexCoordinate(q: radius, r: radius + 1)

    /// The cell at the middle of this chunk.
    public var centre: HexCoordinate {
        Self.basisQ.scaled(by: q) + Self.basisR.scaled(by: r)
    }

    /// Every cell of the chunk, centre first and then outward by ring — the
    /// same fixed order `HexCoordinate.cells(withinRadius:)` gives.
    public var cells: [HexCoordinate] {
        centre.cells(withinRadius: Self.radius)
    }

    /// The chunk a cell falls in.
    ///
    /// Inverting the lattice gives a real-valued guess, which rounding puts
    /// within one of the answer; the nine candidates around it are then tried
    /// in a fixed order and the one that actually contains the cell is
    /// returned. Exactly one does, so the order only matters for reproducing
    /// the walk, not for the result.
    ///
    /// The fallback is unreachable and is written as the rounded guess rather
    /// than a trap: a `fatalError` in the engine is a crash on somebody's
    /// phone, and returning a neighbouring chunk is a wrong colour on a map.
    public static func containing(_ cell: HexCoordinate) -> ChunkCoordinate {
        // The inverse of [[7, 3], [-3, 4]], scaled by its determinant, 37.
        let determinant = Double(cellCount)
        let approximateQ = (4.0 * Double(cell.q) - 3.0 * Double(cell.r)) / determinant
        let approximateR = (3.0 * Double(cell.q) + 7.0 * Double(cell.r)) / determinant

        let guessQ = Int(approximateQ.rounded())
        let guessR = Int(approximateR.rounded())

        for offsetR in -1...1 {
            for offsetQ in -1...1 {
                let candidate = ChunkCoordinate(q: guessQ + offsetQ, r: guessR + offsetR)
                if candidate.centre.distance(to: cell) <= radius { return candidate }
            }
        }
        return ChunkCoordinate(q: guessQ, r: guessR)
    }

    /// Whether a cell falls in this chunk.
    public func contains(_ cell: HexCoordinate) -> Bool {
        centre.distance(to: cell) <= Self.radius
    }

    /// Chunks touching this one, in the same fixed clockwise order cells use.
    public var neighbours: [ChunkCoordinate] {
        HexCoordinate.directions.map { ChunkCoordinate(q: q + $0.q, r: r + $0.r) }
    }

    /// Chunks between here and there. Chunk space is a hex grid like any
    /// other, so this is the ordinary hex distance on the lattice indices.
    public func distance(to other: ChunkCoordinate) -> Int {
        HexCoordinate(q: q, r: r).distance(to: HexCoordinate(q: other.q, r: other.r))
    }

    public static func < (lhs: ChunkCoordinate, rhs: ChunkCoordinate) -> Bool {
        lhs.r == rhs.r ? lhs.q < rhs.q : lhs.r < rhs.r
    }
}
