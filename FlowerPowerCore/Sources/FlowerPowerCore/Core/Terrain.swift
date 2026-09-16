//
//  Terrain.swift
//  FlowerPowerCore
//
//  What the save records about the world: the seed it was drawn from, where
//  the nest stands, which ground has been discovered, and how far the garden
//  has grown. Nothing that can be regenerated is in here — the biomes, the
//  names and eventually the wild flowers all come back out of
//  `WorldGenerator` from the seed, which is why a two-year colony's save is no
//  larger than a two-day one's.
//

/// The world around one colony, as far as it is a matter of record.
public struct Terrain: Codable, Equatable, Sendable {

    /// The seed every chunk is drawn from. Not the colony's seed: the
    /// countryside must not change when the colony's random stream does, and
    /// a colony replayed from a save must find the same ground it left.
    public var seed: UInt64

    /// The chunk the nest is in. The nest itself stands at
    /// `HexCoordinate.origin`, which is why the home chunk is the one whose
    /// centre cell is the origin — `ChunkCoordinate.origin`.
    public var home: ChunkCoordinate

    /// Ground the colony knows about, in the order it came to know it.
    ///
    /// An array rather than a `Set` for one reason and it is the important
    /// one: a `Set` iterated for output comes back in `Hasher` order, which
    /// Swift randomises once per process, and the map would draw itself
    /// differently on every launch. See `PLAN.md` section 4.
    public var discovered: [ChunkCoordinate]

    /// How many rings of the garden are open. One to begin with — the six
    /// cells around the nest, all at 200 m.
    ///
    /// Ten flowers opens the second ring and ten families the third, which is
    /// `MilestoneSystem`'s doing; and planting into a garden that is already
    /// full opens the next one rather than refusing the flower, because
    /// turning away a photograph the player went out and took is the one thing
    /// the garden must never do.
    public var gardenRings: Int

    public init(
        seed: UInt64,
        home: ChunkCoordinate = .origin,
        discovered: [ChunkCoordinate]? = nil,
        gardenRings: Int = 1
    ) {
        self.seed = seed
        self.home = home
        // A founding swarm's scouts have already been over the home chunk and
        // the six around it; that much is known before the first bee flies.
        self.discovered = discovered ?? ([home] + home.neighbours)
        self.gardenRings = max(1, gardenRings)
    }

    /// The generator this terrain's country comes out of.
    public var generator: WorldGenerator { WorldGenerator(seed: seed) }

    /// The home chunk, drawn.
    public var homeChunk: Chunk { generator.chunk(at: home) }

    /// The six chunks around home, drawn, in the fixed clockwise order.
    public var neighbouringChunks: [Chunk] {
        home.neighbours.map(generator.chunk(at:))
    }

    /// The home chunk's biome without building its name.
    ///
    /// `homeChunk` is asked for by the interface a few times a refresh;
    /// `homeBiome` is asked for by `ThreatSystem` once per predator per day,
    /// which is twenty-one string constructions a day for a label nobody
    /// reads. Same arithmetic, none of the naming.
    public var homeBiome: Biome { generator.biome(at: home) }

    /// Everything the colony knows, drawn, in the order it came to know it.
    ///
    /// The map can show more than seven chunks now, so this is what it draws
    /// from. Order is `discovered`'s own — arrival order — which puts the home
    /// chunk and its six first and everything the foragers and the scouts
    /// found after them.
    public var discoveredChunks: [Chunk] {
        discovered.map(generator.chunk(at:))
    }

    // MARK: - The fog

    /// Ground the dancers have pointed at: an undiscovered chunk touching a
    /// discovered one, and within the range a bee can actually fly.
    ///
    /// Derived rather than stored, which is the whole reason it is correct.
    /// A stored rumour would have to be kept in step with every discovery, and
    /// a save that got out of step would show a rumour of ground the colony
    /// already stands on.
    ///
    /// In a fixed order: discovered chunks in arrival order, and each one's
    /// neighbours in `HexCoordinate.directions` order — east first, clockwise.
    /// An array rather than a `Set` for the reason `discovered` is one.
    public var rumoured: [ChunkCoordinate] {
        var known = Set(discovered)
        var result: [ChunkCoordinate] = []

        for chunk in discovered {
            for neighbour in chunk.neighbours {
                guard !known.contains(neighbour) else { continue }
                guard Self.isWithinFlight(neighbour) else { continue }
                known.insert(neighbour)
                result.append(neighbour)
            }
        }
        return result
    }

    /// Whether a chunk is close enough that a bee could have been there.
    ///
    /// Measured to the chunk's centre cell, which is the cell the chunk is
    /// named for. `FlowerPatch.maximumForagingRange` is the engine's own edge
    /// and the only edge the world has: past it a patch's distance efficiency
    /// is zero, so ground out there could never be worth anything even if
    /// somebody drew it.
    public static func isWithinFlight(_ chunk: ChunkCoordinate) -> Bool {
        chunk.centre.metresFromOrigin <= FlowerPatch.maximumForagingRange
    }

    // MARK: - The garden

    /// Every cell of the garden that is open, innermost ring first and
    /// clockwise within each ring.
    ///
    /// This is the planting order and the drawing order, and it is fixed: a
    /// player's garden must keep its shape between launches, so nothing here
    /// may ever be sorted by anything but the ring walk.
    ///
    /// The nest's own cell is not in it. The bees live there.
    public var gardenCells: [HexCoordinate] {
        (1...max(1, gardenRings)).flatMap { HexCoordinate.origin.ring(radius: $0) }
    }

    /// Cells in the ring that would be opened next.
    public func cells(inRing ring: Int) -> [HexCoordinate] {
        HexCoordinate.origin.ring(radius: max(1, ring))
    }

    /// Opens the next ring and hands back the cells it added.
    @discardableResult
    public mutating func openNextRing() -> [HexCoordinate] {
        gardenRings += 1
        return cells(inRing: gardenRings)
    }

    /// Opens rings until at least `rings` are open. Never closes one: a
    /// milestone awarded on a garden that has already grown past it should do
    /// nothing rather than take cells away.
    public mutating func unlockRings(upTo rings: Int) {
        gardenRings = max(gardenRings, rings)
    }

    /// Records ground as known, if it is not already. Order is arrival order.
    public mutating func discover(_ chunk: ChunkCoordinate) {
        guard !discovered.contains(chunk) else { return }
        discovered.append(chunk)
    }

    public func hasDiscovered(_ chunk: ChunkCoordinate) -> Bool {
        discovered.contains(chunk)
    }
}
