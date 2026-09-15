//
//  WorldGenerator.swift
//  FlowerPowerCore
//
//  The countryside, as a pure function of a seed and a coordinate.
//
//  Nothing the generator produces is ever stored. A chunk is regenerated on
//  demand, every time, which is why the save does not grow with the map and
//  why an old save can have a world derived around it. The save records only
//  what has *happened*: which ground has been discovered, what the player has
//  planted. See `Terrain`.
//
//  That makes determinism the whole contract, and a stricter one than the
//  colony's. The colony has to replay identically from a seed within a
//  process; a chunk has to come out the same on the phone, on the watch, in
//  `beesim` on Windows, and in a save opened next year. So the generator never
//  touches `Hasher` — Swift seeds it randomly once per process — never draws
//  from the colony's `SeededRandom`, and never iterates a `Dictionary`. It
//  does integer arithmetic on `(seed, salt, q, r)` and nothing else.
//  `WorldGeneratorTests` pins `chunk(at:)` against literal expected values for
//  a fixed seed, so a change to the hash that looks harmless fails a test
//  rather than quietly moving everybody's map.
//

/// Draws the country around the nest.
public struct WorldGenerator: Equatable, Sendable {

    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    // MARK: - The hash

    /// A small integer hash of a seed, a field salt and a lattice point.
    ///
    /// SplitMix64's mixing function with the coordinates folded in, which is
    /// the same arithmetic `SeededRandom` already trusts. Written out rather
    /// than reusing `SeededRandom` because this is not a stream: the same
    /// point must give the same answer whenever it is asked, in any order, in
    /// any process.
    ///
    /// `Int` is 64-bit on every platform the game targets, and the bit pattern
    /// is taken rather than the value so that negative coordinates — half the
    /// world — mix as well as positive ones.
    static func hash(seed: UInt64, salt: UInt64, q: Int, r: Int) -> UInt64 {
        var z = seed &+ (salt &* 0x9E37_79B9_7F4A_7C15)
        z = z &+ (UInt64(bitPattern: Int64(q)) &* 0xC2B2_AE3D_27D4_EB4F)
        z = z &+ (UInt64(bitPattern: Int64(r)) &* 0x1656_67B1_9E37_79F9)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The hash as a value in 0..<1, the same way `SeededRandom.unitValue`
    /// does it.
    static func unit(seed: UInt64, salt: UInt64, q: Int, r: Int) -> Double {
        Double(hash(seed: seed, salt: salt, q: q, r: r) >> 11)
            * (1.0 / 9_007_199_254_740_992.0)
    }

    // MARK: - The fields

    /// Which of the three noise fields a sample belongs to. The salt is what
    /// keeps them independent of one another; three fields drawn from the same
    /// salt would be the same field.
    enum Field: UInt64 {
        case wetness = 1
        case openness = 2
        case settlement = 3
    }

    /// How many chunks a feature of the landscape spans.
    ///
    /// The fields are sampled on a lattice this many chunks apart and
    /// interpolated between, which is what makes a biome a region rather than
    /// a speckle. Four chunks is about five kilometres — a river valley, a
    /// stretch of moor, a village and its fields. A chunk that straddles two
    /// is the interesting one, and there are enough of them at this scale.
    static let featureChunks = 4

    /// Smooth value noise over chunk coordinates.
    ///
    /// Value noise rather than anything cleverer: it is four hashes and three
    /// interpolations, it is exactly reproducible in integer arithmetic, and
    /// at this scale nobody can tell it from Perlin. The smoothstep is what
    /// stops the biome boundaries following the lattice.
    func field(_ field: Field, at chunk: ChunkCoordinate) -> Double {
        let scale = Double(Self.featureChunks)
        let x = Double(chunk.q) / scale
        let y = Double(chunk.r) / scale

        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let fx = Self.smooth(x - Double(x0))
        let fy = Self.smooth(y - Double(y0))

        let corner00 = Self.unit(seed: seed, salt: field.rawValue, q: x0, r: y0)
        let corner10 = Self.unit(seed: seed, salt: field.rawValue, q: x0 + 1, r: y0)
        let corner01 = Self.unit(seed: seed, salt: field.rawValue, q: x0, r: y0 + 1)
        let corner11 = Self.unit(seed: seed, salt: field.rawValue, q: x0 + 1, r: y0 + 1)

        let top = corner00 + (corner10 - corner00) * fx
        let bottom = corner01 + (corner11 - corner01) * fx
        return top + (bottom - top) * fy
    }

    /// Hermite smoothstep, so the interpolation has no corners in it.
    static func smooth(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    /// How wet the ground is, 0...1.
    public func wetness(at chunk: ChunkCoordinate) -> Double { field(.wetness, at: chunk) }

    /// Grass against trees, 0 closed to 1 open.
    public func openness(at chunk: ChunkCoordinate) -> Double { field(.openness, at: chunk) }

    /// How near people are, 0...1.
    public func settlement(at chunk: ChunkCoordinate) -> Double { field(.settlement, at: chunk) }

    // MARK: - Biome

    /// Which biome the fields add up to.
    ///
    /// Read as a ladder, most decisive first, which is what `WORLD.md`
    /// section 5 describes: settlement overrides everything, because people
    /// are the one thing that replaces whatever was there; then the wet
    /// ground; then the dry open ground; then trees against grass. What falls
    /// between is hedgerow, which is the honest answer — a field margin *is*
    /// the boundary between two other things.
    ///
    /// Wet-and-closed is deliberately not modelled: there is no fen woodland
    /// in the catalogue, so it reads as riverbank, which has the willow in it.
    public func biome(at chunk: ChunkCoordinate) -> Biome {
        let settlement = self.settlement(at: chunk)
        let wetness = self.wetness(at: chunk)
        let openness = self.openness(at: chunk)

        if settlement > 0.72 { return .village }
        if settlement > 0.55, openness > 0.50, wetness < 0.55 { return .farmland }
        if wetness > 0.68 { return .riverbank }
        if wetness < 0.32, openness > 0.55 { return .heath }
        if openness < 0.38 { return .woodland }
        if openness > 0.58 { return .meadow }
        return .hedgerow
    }

    // MARK: - Chunks

    /// The chunk at a coordinate. Pure, and the same every call.
    public func chunk(at coordinate: ChunkCoordinate) -> Chunk {
        let biome = self.biome(at: coordinate)
        return Chunk(
            coordinate: coordinate,
            biome: biome,
            name: name(for: biome, at: coordinate)
        )
    }

    // MARK: - Names

    /// What the ground is called.
    ///
    /// The player never sees "chunk (3, -1)"; they see a stretch of country
    /// with a name. Two words for most of it — a qualifier and a noun the
    /// biome supplies — and for a village the older form that English place
    /// names actually take, a thing at a place: *the Churchyard at
    /// Coldharbour*.
    ///
    /// Drawn from the same hash as the fields, on its own salts, so a chunk's
    /// name is as reproducible as its biome.
    func name(for biome: Biome, at coordinate: ChunkCoordinate) -> String {
        let nouns = Self.nouns(for: biome)
        let noun = nouns[Self.index(seed: seed, salt: 11, coordinate: coordinate, count: nouns.count)]

        guard biome == .village else {
            let qualifier = Self.qualifiers[
                Self.index(seed: seed, salt: 12, coordinate: coordinate, count: Self.qualifiers.count)
            ]
            return "\(qualifier) \(noun)"
        }

        let place = Self.places[
            Self.index(seed: seed, salt: 13, coordinate: coordinate, count: Self.places.count)
        ]
        return "the \(noun) at \(place)"
    }

    /// An index into a word list, from the hash. Modulo rather than a scaled
    /// unit value, so the choice is exact integer arithmetic and cannot move
    /// with the floating-point unit.
    static func index(
        seed: UInt64, salt: UInt64, coordinate: ChunkCoordinate, count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        return Int(hash(seed: seed, salt: salt, q: coordinate.q, r: coordinate.r) % UInt64(count))
    }

    /// English landscape qualifiers, the kind an Ordnance Survey sheet is full
    /// of. Deliberately plain: the name should sound like somewhere, not like
    /// a fantasy map.
    static let qualifiers: [String] = [
        "Mill", "Long", "Hollow", "Nether", "Upper", "Cold", "Broad", "Stony",
        "Fox", "Heron", "Alder", "Ash", "Black", "White", "Old", "Green"
    ]

    /// Villages to hang a churchyard or a lime avenue on.
    static let places: [String] = [
        "Coldharbour", "Nettlebed", "Thornbury", "Marsham", "Oakley",
        "Winterbourne", "Hallowfield", "Draycott", "Stanton", "Belchworth"
    ]

    /// What each kind of ground is called, in a fixed order.
    static func nouns(for biome: Biome) -> [String] {
        switch biome {
        case .meadow: return ["Meadow", "Leas", "Pasture", "Green", "Mead"]
        case .hedgerow: return ["Hedges", "Margin", "Balk", "Headland", "Shaw"]
        case .woodland: return ["Wood", "Copse", "Holt", "Hanger", "Spinney"]
        case .riverbank: return ["Reach", "Withies", "Water", "Carr", "Ford"]
        case .farmland: return ["Field", "Furlong", "Acres", "Tilth", "Stubble"]
        case .village: return ["Churchyard", "Green", "Gardens", "Almshouses", "Lime Walk"]
        case .heath: return ["Bank", "Moor", "Heath", "Down", "Tops"]
        }
    }
}

/// One generated stretch of country.
///
/// A value, not a record: nothing here is saved, and two `Chunk`s from the
/// same seed and coordinate are equal because they are the same arithmetic run
/// twice. `Codable` only so it can ride along on a snapshot to the watch.
public struct Chunk: Codable, Equatable, Sendable, Identifiable {

    public let coordinate: ChunkCoordinate
    public let biome: Biome
    /// What the player sees instead of a coordinate.
    public let name: String

    public init(coordinate: ChunkCoordinate, biome: Biome, name: String) {
        self.coordinate = coordinate
        self.biome = biome
        self.name = name
    }

    public var id: ChunkCoordinate { coordinate }

    /// The cell at the middle of it.
    public var centre: HexCoordinate { coordinate.centre }
}
