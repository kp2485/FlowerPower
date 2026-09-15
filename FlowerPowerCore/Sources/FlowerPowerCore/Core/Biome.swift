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
}
