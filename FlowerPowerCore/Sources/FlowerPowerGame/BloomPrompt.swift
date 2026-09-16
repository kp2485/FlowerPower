//
//  BloomPrompt.swift
//  FlowerPowerGame
//
//  What is out there to photograph this month.
//
//  The simulation keeps its own calendar — a colony founded in September
//  starts in simulated spring — but a player going for a walk is in the real
//  one. This works from the real date and the hemisphere, and from nothing
//  more: the game never learns where the player is, and does not need to.
//

import Foundation
import FlowerPowerCore

/// Which half of the year the player's flowers keep. Chosen in settings, which
/// is one tap and answers the only geographic question the game ever has.
public enum Hemisphere: String, Codable, Sendable {
    case northern
    case southern
}

public enum RealSeason {

    /// Meteorological seasons, which are the ones flowers keep: spring is
    /// March to May in the north, September to November in the south.
    public static func current(
        on date: Date = Date(),
        in hemisphere: Hemisphere = .northern,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Season {
        let month = calendar.component(.month, from: date)
        let northern: Season
        switch month {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .autumn
        default: northern = .winter
        }

        guard hemisphere == .southern else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

public struct BloomPrompt: Equatable, Sendable {

    public let season: Season
    /// Everything in the catalogue that flowers now.
    public let inBloom: [FlowerSpecies]
    /// The ones the player has not yet photographed, best forage first.
    public let notYetPhotographed: [FlowerSpecies]
    /// Families flowering now that the garden has no member of.
    public let missingFamilies: [PlantFamily]
    /// Plants that flower when little else does. Worth pointing out.
    public let keystones: [FlowerSpecies]

    /// Where a keystone is in flower out in the country, when the colony knows
    /// of one: "Heather is out on Heather Bank, to the north-east."
    ///
    /// The one sentence in the game that gives a direction, and it earns it —
    /// a flow, in this world, is a *place*, and the colony's year is a
    /// sequence of directions the dancers point in. Nil until the bees have
    /// found ground with a keystone on it, which is most of the time.
    ///
    /// Not a nudge to photograph anything. The heather is already being
    /// worked; this says so.
    public let wildKeystone: String?

    public init(
        date: Date = Date(),
        hemisphere: Hemisphere = .northern,
        patches: [PatchSummary],
        terrain: TerrainSummary? = nil,
        wildPatches: [PatchSummary] = []
    ) {
        let season = RealSeason.current(on: date, in: hemisphere)
        let collection = BotanyCollection(patches: patches)
        self.wildKeystone = Self.wildKeystoneSentence(
            patches: wildPatches, terrain: terrain, season: season
        )

        let flowering = FlowerCatalogue.inBloom(during: season)
        self.season = season
        self.inBloom = flowering
        self.notYetPhotographed = flowering.filter { !collection.speciesCollected.contains($0.id) }
        self.keystones = flowering.filter(\.isKeystone)

        let familiesFlowering = Set(flowering.map(\.family))
        let familiesHeld = Set(collection.families.map(\.family))
        self.missingFamilies = familiesFlowering.subtracting(familiesHeld)
            .sorted { $0.scientificName < $1.scientificName }
    }

    /// Finds a keystone standing wild on ground the colony knows, and says
    /// where it is.
    ///
    /// Read off the patches rather than off the generator, and that is the
    /// honest way round: a wild patch is only in `patches` at all once a bee
    /// has been to its chunk, so this can never point at country nobody has
    /// seen. The chunk is resolved through `TerrainSummary.chunk(containing:)`
    /// for the same reason.
    ///
    /// Patch order is registration order, which is discovery order, so the
    /// first keystone found is the first one the colony found — a fixed
    /// answer rather than whichever way a set happened to iterate.
    private static func wildKeystoneSentence(
        patches: [PatchSummary],
        terrain: TerrainSummary?,
        season: Season
    ) -> String? {
        guard let terrain else { return nil }

        for patch in patches {
            guard patch.origin == .wild, let cell = patch.cell, let taxon = patch.taxon else {
                continue
            }
            guard let species = FlowerCatalogue.all.first(where: { $0.taxon == taxon }),
                  species.isKeystone,
                  species.isInBloom(during: season)
            else { continue }

            guard let chunk = terrain.chunk(containing: cell) else { continue }
            guard let bearing = terrain.home.centre.direction(to: chunk.centre) else { continue }

            return "\(species.commonName) is out on \(chunk.name), to the \(bearing)."
        }
        return nil
    }

    public var isEmpty: Bool { inBloom.isEmpty }

    /// One sentence for a notification or a card.
    public var headline: String {
        if let first = notYetPhotographed.first {
            return "\(first.commonName) is out now, and your garden has none."
        }
        if let keystone = keystones.first {
            return "\(keystone.commonName) is flowering — one of the plants that carries a colony through the gaps."
        }
        return "\(inBloom.count) of the flowers your bees work are out this \(season.rawValue)."
    }
}
