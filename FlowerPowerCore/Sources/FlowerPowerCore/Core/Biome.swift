//
//  Biome.swift
//  FlowerPowerCore
//
//  The seven kinds of country the world is made of.
//
//  They come from the field guide rather than the other way round. The thirty
//  species in `FlowerCatalogue` already say where they grow — "in every mown
//  lawn", "in stands along riverbanks", "colouring whole moors from August" —
//  so the table below is the catalogue sorted by habitat rather than a set of
//  places invented and then stocked.
//
//  Phase 1 uses the biome only for a name and a colour on the map. The species
//  lists are here already because Phase 2 needs them to place wild patches,
//  and because writing them down now is what makes `BiomeTests` able to assert
//  that every identifier in them resolves — a typo in a list nobody reads yet
//  is a typo that surfaces months later as an empty hedgerow.
//

/// A stretch of country, as the generator classifies it.
public enum Biome: String, Codable, CaseIterable, Sendable, Comparable {

    case meadow
    case hedgerow
    case woodland
    case riverbank
    case farmland
    case village
    case heath

    /// `CaseIterable` order, so anything that needs a deterministic sequence
    /// of biomes can sort rather than iterate a dictionary.
    public static func < (lhs: Biome, rhs: Biome) -> Bool {
        guard let left = allCases.firstIndex(of: lhs),
              let right = allCases.firstIndex(of: rhs)
        else { return false }
        return left < right
    }

    public var displayName: String {
        switch self {
        case .meadow: return "Meadow"
        case .hedgerow: return "Hedgerow"
        case .woodland: return "Woodland"
        case .riverbank: return "Riverbank"
        case .farmland: return "Farmland"
        case .village: return "Village"
        case .heath: return "Heath"
        }
    }

    /// What the ground is like, in a sentence a player can read the year off.
    ///
    /// Written to the pattern `HiveLocationType.summary` set: what it is, and
    /// then the one thing about it that decides how a colony fares there. An
    /// exhaustive switch over an engine type, so adding a biome fails to build
    /// rather than quietly leaving a map label empty.
    public var summary: String {
        switch self {
        case .meadow:
            return "Clover, dandelion and thistle in grass. Something out from "
                + "spring to autumn, never a flow and never nothing."
        case .hedgerow:
            return "Hawthorn, bramble and ivy along the field margins. A spring "
                + "flow, bramble all summer, and the last forage of the year."
        case .woodland:
            return "Bluebells the bees can barely reach and foxgloves they "
                + "cannot. Safe, shaded and hungry until the ivy comes."
        case .riverbank:
            return "Willow on the damp ground and balsam in stands along the "
                + "water. The first flow of the year, and the last big one."
        case .farmland:
            return "Rape and sunflowers by the field. One enormous fortnight of "
                + "yellow, and very little on either side of it."
        case .village:
            return "Gardens, churchyard and street limes. The only ground in "
                + "the game with something in flower all winter."
        case .heath:
            return "Heather and bugloss on acid, peaty ground. Nearly nothing "
                + "until August, and then the richest flow there is."
        }
    }

    /// Catalogue identifiers of what grows here, in a fixed order.
    ///
    /// Taken from the field notes: each species is listed under the ground its
    /// note describes. A few appear twice on purpose — hawthorn and ivy grow
    /// in a hedge and on a woodland ride, meadowsweet on a damp meadow and a
    /// ditch side — because that is true, and because a biome that shares
    /// nothing with its neighbours makes the map a set of islands rather than
    /// a country.
    ///
    /// Identifiers rather than `FlowerSpecies` values so this stays a plain
    /// table: `FlowerCatalogue.species(withID:)` resolves them, and
    /// `BiomeTests` checks that every one of them does.
    public var species: [String] {
        switch self {
        case .meadow:
            return ["white_clover", "dandelion", "thistle", "meadowsweet"]
        case .hedgerow:
            return ["hawthorn", "bramble", "borage", "phacelia", "poppy", "ivy"]
        case .woodland:
            return ["bluebell", "foxglove", "hawthorn", "ivy"]
        case .riverbank:
            return ["willow", "balsam", "meadowsweet"]
        case .farmland:
            return ["oilseed_rape", "sunflower", "phacelia", "poppy"]
        case .village:
            return [
                "crocus", "lavender", "echinacea", "aster", "sedum", "rosemary",
                "winter_heather", "mahonia", "lime", "apple", "cherry"
            ]
        case .heath:
            return ["heather", "goldenrod", "vipers_bugloss"]
        }
    }

    /// The species themselves, resolved through the catalogue.
    ///
    /// Anything that fails to resolve is dropped rather than crashing, for the
    /// same reason `ChunkCoordinate.containing` does not trap: a missing
    /// flower is a thinner hedge, and a trap is somebody's phone closing.
    public var flowers: [FlowerSpecies] {
        species.compactMap(FlowerCatalogue.species(withID:))
    }

    // MARK: - How much grows there

    /// Wild patches the generator places in one 37-cell chunk of this ground.
    ///
    /// Sparse on purpose. Most of a chunk is grass, canopy or crop with
    /// nothing a bee can work; four to six stands in a parish is what a
    /// hedgerow, a strip of headland and a corner of nettles actually amounts
    /// to. The numbers differ by how much of the ground is workable rather
    /// than by how good it is — a wood is mostly closed canopy, a village is
    /// gardens all the way through — and how *rich* each stand is belongs to
    /// `wildAbundance` below, so the two levers stay separable when they are
    /// swept.
    public var wildPatchCount: Int {
        switch self {
        case .meadow: return 6
        case .hedgerow: return 5
        case .woodland: return 4
        case .riverbank: return 5
        case .farmland: return 4
        case .village: return 6
        case .heath: return 4
        }
    }

    /// How big a wild stand of this ground runs, against the world's
    /// `SimulationConfig.wildPatchYield`.
    ///
    /// A field of rape is one stand and it is enormous; a bluebell carpet is
    /// one stand the bees can barely reach into. This is the per-biome base
    /// `WORLD.md` section 5 asks for, and it is deliberately the smaller of
    /// the two levers: the shape of a biome's year comes from its species'
    /// bloom calendars, not from this.
    public var wildAbundance: Double {
        switch self {
        case .meadow: return 1.0
        case .hedgerow: return 1.0
        case .woodland: return 0.8
        case .riverbank: return 1.0
        case .farmland: return 1.4
        case .village: return 0.9
        case .heath: return 1.3
        }
    }

    // MARK: - Who hunts there, and what is going round

    /// What a predator's daily chance is multiplied by on this ground.
    ///
    /// The table is `WORLD.md` section 4's "who hunts there" column and
    /// nothing else. A predator on the ground it belongs to is between 1.5 and
    /// 2.0; everywhere else it is `elsewhere`, which is well below one — the
    /// point is not that a badger is impossible in a village but that a wood
    /// is badger country and a churchyard is not.
    ///
    /// This is also what quietly makes the roster coherent. It is North
    /// American as much as British — bear, raccoon, skunk, opossum — and
    /// assigning each animal to the ground it belongs on lets the game be
    /// nowhere in particular rather than pretending to be somewhere and
    /// getting it wrong.
    ///
    /// Written as nested switches rather than a dictionary for the reason the
    /// whole engine avoids them: a `Dictionary` is iterated in `Hasher` order,
    /// and while this one is only ever looked up, a table nobody can
    /// accidentally iterate is a table that cannot go wrong.
    public func predatorMultiplier(for predator: Predator) -> Double {
        let elsewhere = 0.6

        switch self {
        case .meadow:
            switch predator {
            case .badger: return 1.7
            case .toad: return 1.7
            case .ant: return 1.6
            case .crabSpider: return 1.9
            default: return elsewhere
            }
        case .hedgerow:
            switch predator {
            case .wasp: return 1.7
            case .hornet: return 1.8
            case .mouse: return 1.6
            case .shrike: return 1.9
            default: return elsewhere
            }
        case .woodland:
            switch predator {
            case .badger: return 1.9
            case .woodpecker: return 2.0
            case .honeyBuzzard: return 1.9
            case .mouse: return 1.7
            case .waxMoth: return 1.6
            default: return elsewhere
            }
        case .riverbank:
            switch predator {
            case .toad: return 1.9
            case .dragonfly: return 1.9
            case .mouse: return 1.6
            default: return elsewhere
            }
        case .farmland:
            switch predator {
            // The farmer, as the `human` catastrophe: a chunk of arable is
            // where a hive is sprayed, mown round or simply moved.
            case .human: return 1.8
            case .robberBee: return 1.9
            case .ant: return 1.5
            default: return elsewhere
            }
        case .village:
            switch predator {
            case .wasp: return 2.0
            case .raccoon: return 1.8
            case .opossum: return 1.6
            case .skunk: return 1.7
            case .human: return 1.5
            default: return elsewhere
            }
        case .heath:
            switch predator {
            case .shrike: return 1.7
            case .prayingMantis: return 1.7
            case .beeEater: return 1.8
            case .bear: return 2.0
            default: return elsewhere
            }
        }
    }

    /// What a pathogen's daily arrival chance is multiplied by on this ground.
    ///
    /// Three claims and no more. **Nosema** is a wet-ground disease: its
    /// spores persist in damp and a cluster that cannot fly to void itself
    /// carries it, so a riverbank is the worst place for it and a dry heath
    /// the best. **Chalkbrood** is a fungus of a damp, cool, shaded nest,
    /// which is a wood. **Varroa is neutral everywhere**, because it arrives
    /// on bees rather than out of the ground, and pretending the moor has
    /// fewer mites would be inventing an effect to fill a row of the table.
    /// Foulbrood leans on where other people's bees are.
    public func pathogenMultiplier(for pathogen: Pathogen) -> Double {
        switch pathogen {
        case .varroa, .deformedWingVirus:
            return 1.0

        case .nosema:
            switch self {
            case .riverbank: return 1.8
            case .meadow: return 1.2
            case .woodland: return 1.1
            case .village: return 1.0
            case .hedgerow: return 0.9
            case .farmland: return 0.9
            case .heath: return 0.7
            }

        case .chalkbrood:
            switch self {
            case .woodland: return 1.8
            case .riverbank: return 1.4
            case .hedgerow: return 1.0
            case .meadow: return 0.9
            case .village: return 0.9
            case .farmland: return 0.8
            case .heath: return 0.7
            }

        case .americanFoulbrood:
            // It travels in robbed honey and on secondhand comb, so it is a
            // disease of places with other colonies in them.
            switch self {
            case .farmland: return 1.5
            case .village: return 1.3
            case .hedgerow: return 1.0
            case .meadow: return 1.0
            case .riverbank: return 0.9
            case .woodland: return 0.8
            case .heath: return 0.8
            }
        }
    }
}

// MARK: - Turning a table down

extension SimulationConfig {

    /// Scales a biome multiplier's *deviation* from one, so the whole biome
    /// effect can be turned off with a single number.
    ///
    /// `biomeThreatScale = 0` gives 1.0 for everything, which is the engine
    /// exactly as it was before biomes touched it — the row every measurement
    /// of the tables is taken against. `1` is the table as written, and
    /// anything above it widens the spread between biomes without anybody
    /// having to edit fourteen numbers by hand.
    public func scaled(_ multiplier: Double) -> Double {
        max(0, 1 + (multiplier - 1) * biomeThreatScale)
    }
}
