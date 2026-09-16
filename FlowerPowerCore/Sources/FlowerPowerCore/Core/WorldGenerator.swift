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

    // MARK: - Wild flowers

    /// What grows wild in a chunk, and where.
    ///
    /// The generator's output is a *description* rather than a `FlowerPatch`:
    /// it says which cell, which species and how big the stand runs, and
    /// nothing about identifiers, capacity or the day. That is deliberate.
    /// Patches carry ids from the colony's `IDGenerator` and state the save
    /// has to keep, and neither of those can come out of a pure function of a
    /// coordinate — so the generator describes the ground and
    /// `World.discover(_:ids:config:)` is what turns a description into a
    /// patch, once, at the moment a bee finds it.
    public struct WildPatchSeed: Equatable, Sendable {

        /// Where it stands. Its distance from the nest follows from this.
        public let cell: HexCoordinate

        /// A `FlowerCatalogue` identifier.
        public let speciesID: String

        /// How big this particular stand is, against the biome's own base.
        /// Around 1.0, and multiplied by `Biome.wildAbundance` and the world's
        /// `SimulationConfig.wildPatchYield` to reach the patch's
        /// `capacityScale`.
        public let variation: Double

        public init(cell: HexCoordinate, speciesID: String, variation: Double) {
            self.cell = cell
            self.speciesID = speciesID
            self.variation = variation
        }
    }

    /// Salts for the wild-flower draws. Distinct from the field salts above,
    /// so moving a biome boundary does not shuffle every hedge in the county.
    private enum WildSalt: UInt64 {
        case placement = 21
        case species = 22
        case size = 23
    }

    /// The wild flowers of a chunk, in the chunk's own fixed cell order.
    ///
    /// Choosing *k* of the 37 cells without an RNG stream: every cell is given
    /// a hash, and the *k* smallest win, ties broken by the cell's position in
    /// the walk. That is a stable selection with no state, which is what lets
    /// a chunk be regenerated identically whenever anybody asks — on the
    /// phone, on the watch, and in a save opened next year.
    ///
    /// Species are drawn from the biome's list weighted by the catalogue's
    /// rarity, common most: a hedge is mostly bramble with the odd stand of
    /// something better, which is the whole reason `FlowerRarity` exists.
    /// Integer arithmetic throughout — a modulo of the hash — so nothing here
    /// can move with the floating-point unit.
    /// - Parameter density: multiplies the biome's own count, so how thick the
    ///   country is can be swept without editing seven numbers. One is the
    ///   table as written. The *choice* of cells does not move with it — the
    ///   ranking is the same ranking and a denser world simply takes more of
    ///   it — so raising the density adds hedges rather than rearranging them.
    public func wildPatches(
        in coordinate: ChunkCoordinate, density: Double = 1
    ) -> [WildPatchSeed] {
        let biome = self.biome(at: coordinate)
        let cells = coordinate.cells
        let scaled = Int((Double(biome.wildPatchCount) * max(0, density)).rounded())
        let wanted = min(scaled, cells.count)
        guard wanted > 0 else { return [] }

        // Rank the cells by their placement hash. The cell's position in the
        // walk is the tie-break, so two cells that hash the same still come
        // out in a fixed order.
        struct Ranked {
            let position: Int
            let cell: HexCoordinate
            let key: UInt64
        }

        var ranked: [Ranked] = []
        ranked.reserveCapacity(cells.count)
        for (position, cell) in cells.enumerated() {
            let key = Self.hash(
                seed: seed, salt: WildSalt.placement.rawValue, q: cell.q, r: cell.r
            )
            ranked.append(Ranked(position: position, cell: cell, key: key))
        }
        ranked.sort { left, right in
            left.key == right.key ? left.position < right.position : left.key < right.key
        }

        let weighted = Self.weightedSpecies(for: biome)
        guard !weighted.isEmpty else { return [] }

        // Back into cell order before returning, so the patches of a chunk are
        // always created in the same sequence and take their identifiers from
        // the colony's counter in that sequence.
        let chosen = ranked.prefix(wanted).sorted { $0.position < $1.position }

        var seeds: [WildPatchSeed] = []
        seeds.reserveCapacity(chosen.count)
        for entry in chosen {
            let draw = Self.hash(
                seed: seed, salt: WildSalt.species.rawValue, q: entry.cell.q, r: entry.cell.r
            )
            let index = Int(draw % UInt64(weighted.count))
            // A stand is 0.7 to 1.3 of the biome's base. Enough that two hedges
            // are not the same hedge; not enough that the ground's character
            // comes from the dice.
            let size = Self.unit(
                seed: seed, salt: WildSalt.size.rawValue, q: entry.cell.q, r: entry.cell.r
            )
            seeds.append(WildPatchSeed(
                cell: entry.cell,
                speciesID: weighted[index],
                variation: 0.7 + size * 0.6
            ))
        }
        return seeds
    }

    /// The biome's species list with each identifier repeated by how common
    /// the plant is, so a uniform draw over the expanded list is a draw
    /// weighted by rarity.
    ///
    /// An array rather than a running total because the lists are five to
    /// eleven entries long: the expanded list is at most thirty-odd strings,
    /// built once per chunk, and it makes the weighting something a reader can
    /// see rather than something they have to trust.
    static func weightedSpecies(for biome: Biome) -> [String] {
        var expanded: [String] = []
        for identifier in biome.species {
            let rarity = FlowerCatalogue.species(withID: identifier)?.rarity ?? .common
            let weight: Int
            switch rarity {
            case .common: weight = 4
            case .uncommon: weight = 2
            case .rare: weight = 1
            }
            expanded.append(contentsOf: repeatElement(identifier, count: weight))
        }
        return expanded
    }

    /// How much of a chunk's wild forage is actually standing on a given day.
    ///
    /// Capacity times whether the plant is in flower, summed over the chunk.
    /// It is what `ExplorationSystem` weighs a rumoured chunk by: a forager
    /// blundering into the next parish is far more likely to come back with
    /// news of it when there is a field of rape in it than when there is
    /// nothing out, which is the only sense in which the bees can be said to
    /// choose where they explore.
    public func wildRichness(
        in coordinate: ChunkCoordinate, during season: Season, density: Double = 1
    ) -> Double {
        let biome = self.biome(at: coordinate)
        return wildPatches(in: coordinate, density: density).reduce(0.0) { total, seed in
            guard let species = FlowerCatalogue.species(withID: seed.speciesID),
                  species.isInBloom(during: season)
            else { return total }
            return total + seed.variation * biome.wildAbundance
        }
    }

    /// The first seed at or after `start` whose home chunk is this biome.
    ///
    /// For `beesim --biome`, and for a test that wants particular ground
    /// underfoot. A linear scan rather than anything clever: the fields are
    /// smooth noise and every biome turns up within a few hundred seeds, and a
    /// scan is reproducible where a solver would not be.
    ///
    /// Returns nil rather than looping forever if a biome cannot be found
    /// within `limit` — a caller that asked for the impossible gets to say so.
    public static func seed(producing biome: Biome, from start: UInt64, limit: Int = 100_000) -> UInt64? {
        for offset in 0..<limit {
            let candidate = start &+ UInt64(offset)
            if WorldGenerator(seed: candidate).biome(at: .origin) == biome { return candidate }
        }
        return nil
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
