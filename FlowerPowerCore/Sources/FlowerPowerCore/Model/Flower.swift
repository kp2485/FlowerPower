//
//  Flower.swift
//  FlowerPowerCore
//
//  Photographed flowers are the game's only source of forage. Identification
//  is a bonus: an unrecognised flower still feeds the hive, at generic yield,
//  so a poor photo degrades the reward instead of breaking the loop.
//

import Foundation

// MARK: - Geography

public struct GeoPoint: Codable, Hashable, Sendable {

    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres. Haversine is ample at foraging range,
    /// and avoids pulling CoreLocation into the engine — which would cost us
    /// the ability to test it off-device.
    public func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let phi1 = latitude * .pi / 180
        let phi2 = other.latitude * .pi / 180
        let deltaPhi = (other.latitude - latitude) * .pi / 180
        let deltaLambda = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))

        return earthRadius * c
    }
}

// MARK: - Species

public enum FlowerRarity: String, Codable, CaseIterable, Sendable {
    case common
    case uncommon
    case rare

    /// Multiplier applied to a patch's total forage.
    public var yieldMultiplier: Double {
        switch self {
        case .common: return 1.0
        case .uncommon: return 1.6
        case .rare: return 2.5
        }
    }

    public var displayName: String { rawValue.capitalized }
}

public struct FlowerSpecies: Codable, Hashable, Identifiable, Sendable {

    /// Stable identifier. Also the label a trained classifier is expected to
    /// emit, though `ClassifierLabels` will translate most other vocabularies.
    public let id: String
    public let commonName: String

    /// Where the plant sits botanically. Carries the family, which is what
    /// governs floral architecture and therefore whether a honey bee can work
    /// the flower at all.
    public let taxon: Taxon

    public let rarity: FlowerRarity

    /// Seasons in which this plant is actually in bloom. Photographing a
    /// crocus in August banks the sighting but yields nothing until spring.
    public let bloomSeasons: Set<Season>

    /// Some plants are worth far more than their raw yield suggests, because
    /// they bloom when nothing else does.
    public let isKeystone: Bool

    /// Measured properties of the flower. Defaults to what the family
    /// typically offers, which is the honest estimate when nobody has measured
    /// this particular plant.
    public let traits: FloralTraits

    public init(
        id: String,
        commonName: String,
        taxon: Taxon,
        rarity: FlowerRarity = .common,
        bloomSeasons: Set<Season> = [.spring, .summer],
        isKeystone: Bool = false,
        traits: FloralTraits? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.taxon = taxon
        self.rarity = rarity
        self.bloomSeasons = bloomSeasons
        self.isKeystone = isKeystone
        self.traits = traits ?? taxon.family.typicalTraits
    }

    public var scientificName: String? { taxon.scientificName }
    public var family: PlantFamily { taxon.family }

    /// Nectar a colony can actually bank from this plant, relative to an
    /// ordinary flower.
    ///
    /// Derived rather than stored. It used to be a hand-chosen number; it is
    /// now the consequence of how deep the corolla is, how much nectar is in
    /// it, and how concentrated that nectar is — which is why red clover and
    /// white clover, the same genus with similar nectar, differ so sharply.
    public var nectarRichness: Double {
        traits.sugarYield / FloralTraits.referenceSugarYield
    }

    public var pollenRichness: Double { traits.effectivePollenYield }

    public func isInBloom(during season: Season) -> Bool {
        bloomSeasons.contains(season)
    }

    /// Whether a honey bee is essentially locked out of the nectar.
    public var nectarIsOutOfReach: Bool { traits.isOutOfReach }

    /// Stand-in for a photograph that could not be placed even to a family.
    ///
    /// Deliberately playable rather than punishing: a middling flower of no
    /// particular distinction, which is a fair guess about a plant nobody can
    /// name, and assumed to bloom in the warm seasons so it is never dead
    /// weight.
    public static let unidentified = FlowerSpecies(
        id: "unidentified",
        commonName: "Unidentified Flower",
        taxon: Taxon(family: .rosaceae),
        rarity: .common,
        bloomSeasons: [.spring, .summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 4,
            nectarSugarConcentration: 0.30,
            nectarVolume: 0.6,
            pollenProteinFraction: 0.18,
            pollenAminoAcidCompleteness: 0.85,
            pollenAbundance: 0.6
        )
    )

    /// The best description available for a plant placed only to a family or a
    /// genus.
    ///
    /// This is what makes a coarse identification useful rather than a
    /// consolation prize. A photograph placed in Boraginaceae is known to be a
    /// good nectar plant with a corolla a honey bee can work, even if nobody
    /// can say whether it is borage or viper's bugloss — so the colony gets
    /// the family's typical forage rather than the generic unknown.
    public static func generic(for taxon: Taxon) -> FlowerSpecies {
        let relatives = FlowerCatalogue.all.filter { taxon.contains($0.taxon) }

        // Where the catalogue has members of this group, their average is a
        // better estimate than the family-wide default.
        let traits = relatives.isEmpty
            ? taxon.family.typicalTraits
            : FloralTraits.mean(of: relatives.map(\.traits))

        let seasons = relatives.isEmpty
            ? Set(Season.allCases).subtracting([.winter])
            : relatives.reduce(into: Set<Season>()) { $0.formUnion($1.bloomSeasons) }

        return FlowerSpecies(
            id: "taxon:\(taxon.scientificName)",
            commonName: taxon.rank == .family
                ? taxon.family.commonName
                : taxon.scientificName,
            taxon: taxon,
            rarity: .common,
            bloomSeasons: seasons,
            isKeystone: relatives.contains(where: \.isKeystone),
            traits: traits
        )
    }
}

extension FloralTraits {

    /// Average of a set of traits, for describing a genus or family by its
    /// known members.
    static func mean(of traits: [FloralTraits]) -> FloralTraits {
        guard !traits.isEmpty else {
            return PlantFamily.rosaceae.typicalTraits
        }

        let count = Double(traits.count)
        func average(_ value: (FloralTraits) -> Double) -> Double {
            traits.map(value).reduce(0, +) / count
        }

        return FloralTraits(
            corollaDepthMillimetres: average(\.corollaDepthMillimetres),
            nectarSugarConcentration: average(\.nectarSugarConcentration),
            nectarVolume: average(\.nectarVolume),
            pollenProteinFraction: average(\.pollenProteinFraction),
            pollenAminoAcidCompleteness: average(\.pollenAminoAcidCompleteness),
            pollenAbundance: average(\.pollenAbundance),
            // Nectarless only if every member is. A genus with one nectarless
            // species is still a genus worth visiting for nectar.
            producesNectar: traits.contains { $0.producesNectar }
        )
    }
}

// MARK: - Patches

/// Where a patch came from.
public enum PatchOrigin: String, Codable, Sendable, CaseIterable {
    /// The player found it and photographed it.
    case photographed
    /// Somebody sent it to them.
    case shared
}

/// One photographed flower, which becomes a depleting forage patch on the map.
public struct FlowerPatch: Identifiable, Codable, Equatable, Sendable {

    public let id: EntityID

    /// Local photo library identifier. The image itself never enters the
    /// simulation — the engine stays free of any platform image type.
    public let photoLocalIdentifier: String

    /// `nil` until classification runs; falls back to `.unidentified`.
    public var species: FlowerSpecies?

    /// Classifier confidence in 0...1, which scales the patch's yield.
    public var identificationConfidence: Double

    /// From photo EXIF, when the user has granted location. Optional
    /// throughout: the game must be playable with location denied.
    public var coordinate: GeoPoint?

    /// Distance from the hive in metres, resolved when the patch is registered.
    /// Falls back to a nominal mid-range distance when there is no location, so
    /// denying location permission costs accuracy but never breaks the game.
    public var distanceMetres: Double

    public let discoveredAt: Date

    /// Simulated day the photograph entered the world, which is what the
    /// patch's fading is measured from.
    ///
    /// Optional only for compatibility: patches saved before fading existed
    /// have no registration day, and are grandfathered as never fading rather
    /// than being given a fabricated one that would age them out instantly.
    public var registeredOnDay: Int?

    /// How the patch got here.
    ///
    /// Optional for the same reason as `registeredOnDay`: a patch saved before
    /// flowers could be shared was necessarily one the player found, so a
    /// missing value means `.photographed` rather than being an error.
    public var storedOrigin: PatchOrigin?

    /// Who sent it, when somebody did. Display only — the simulation does not
    /// care, but a garden full of anonymous flowers loses the point of having
    /// been given them.
    public var sharedBy: String?

    public var origin: PatchOrigin { storedOrigin ?? .photographed }
    public var isShared: Bool { origin == .shared }

    public var remainingNectar: Double
    public var remainingPollen: Double

    /// Standing capacity, which the patch regrows toward while in bloom.
    public let nectarCapacity: Double
    public let pollenCapacity: Double

    /// Foragers currently committed to this patch by the waggle dance.
    public var recruitedForagers: Int

    public init(
        id: EntityID,
        photoLocalIdentifier: String,
        species: FlowerSpecies? = nil,
        identificationConfidence: Double = 0,
        coordinate: GeoPoint? = nil,
        distanceMetres: Double = FlowerPatch.nominalDistance,
        discoveredAt: Date,
        registeredOnDay: Int? = nil,
        origin: PatchOrigin = .photographed,
        sharedBy: String? = nil,
        capacityScale: Double = 1
    ) {
        self.id = id
        self.photoLocalIdentifier = photoLocalIdentifier
        self.species = species
        self.identificationConfidence = identificationConfidence
        self.coordinate = coordinate
        self.distanceMetres = max(0, distanceMetres)
        self.discoveredAt = discoveredAt
        self.registeredOnDay = registeredOnDay
        self.storedOrigin = origin
        self.sharedBy = sharedBy
        self.recruitedForagers = 0

        let resolved = species ?? .unidentified
        // A confident identification is worth roughly 40% more forage than a
        // guess, so identifying is rewarding without being mandatory.
        let confidenceBonus = 1.0 + 0.4 * max(0, min(1, identificationConfidence))
        // `capacityScale` is how a shared flower is worth less than one the
        // player found. Applied here rather than at harvest so that everything
        // downstream — regrowth ceiling, forage quality, the fraction the
        // garden shows — is consistent about how big the patch is.
        let scale = resolved.rarity.yieldMultiplier * confidenceBonus * max(0, capacityScale)

        self.nectarCapacity = Self.baseCapacity * resolved.nectarRichness * scale
        self.pollenCapacity = Self.baseCapacity * resolved.pollenRichness * scale
        self.remainingNectar = nectarCapacity
        self.remainingPollen = pollenCapacity
    }

    /// Total forage a plain common flower holds when full.
    public static let baseCapacity: Double = 120

    /// Assumed distance when a photo carries no location.
    public static let nominalDistance: Double = 800

    /// Honey bees forage within about a five-mile radius, but the economics
    /// collapse long before that.
    public static let maximumForagingRange: Double = 8_000

    // MARK: - Fading

    /// How much of the stand is still there, from 1 down to 0.
    ///
    /// A photograph is a record of flowers on one day. Months later the clover
    /// has been mown, the bramble has been cut back, the balsam has been pulled
    /// or the whole verge has been built on. Nothing in a garden stays put, and
    /// a patch that yields for ever turns the premise of the game into a lie:
    /// measured before this existed, results from five photographs upward were
    /// byte-identical, so after an afternoon's play no photograph the player
    /// took ever changed anything again.
    ///
    /// Fading is what gives ongoing photography a job. It is deliberately slow
    /// enough to be a habit rather than a chore: a patch holds full strength
    /// for `freshDays` and then declines over `fadeDays`.
    public func vigour(onDay day: Int, fresh freshDays: Int, fade fadeDays: Int) -> Double {
        // Grandfathered: saved before fading existed.
        guard let registeredOnDay else { return 1 }

        let age = day - registeredOnDay
        guard age > freshDays else { return 1 }
        guard fadeDays > 0 else { return 0 }

        let faded = Double(age - freshDays) / Double(fadeDays)
        return max(0, 1 - faded)
    }

    public func vigour(onDay day: Int, config: SimulationConfig) -> Double {
        vigour(onDay: day, fresh: config.patchFreshDays, fade: config.patchFadeDays)
    }

    /// Nothing left worth flying to.
    public func hasFaded(onDay day: Int, config: SimulationConfig) -> Bool {
        vigour(onDay: day, config: config) <= 0
    }

    /// Standing capacity after fading. What the patch regrows toward.
    public func nectarCapacity(onDay day: Int, config: SimulationConfig) -> Double {
        nectarCapacity * vigour(onDay: day, config: config)
    }

    public func pollenCapacity(onDay day: Int, config: SimulationConfig) -> Double {
        pollenCapacity * vigour(onDay: day, config: config)
    }

    public var resolvedSpecies: FlowerSpecies { species ?? .unidentified }
    public var isDepleted: Bool { remainingNectar <= 0.01 && remainingPollen <= 0.01 }
    public var isIdentified: Bool { species != nil }

    public func isInBloom(during season: Season) -> Bool {
        resolvedSpecies.isInBloom(during: season)
    }

    public var isWithinRange: Bool { distanceMetres <= Self.maximumForagingRange }

    /// Net efficiency of working this patch, accounting for the flight there
    /// and back. A bee burns honey to fly, so a distant patch returns less than
    /// it appears to — and past the foraging range, nothing at all.
    public var distanceEfficiency: Double {
        guard isWithinRange else { return 0 }
        // Falls from 1.0 at the hive entrance to roughly 0.25 at 5 km.
        return 1.0 / (1.0 + distanceMetres / 1_600.0)
    }

    /// How attractive this patch is to a scout deciding whether to dance for
    /// it. Real bees weigh sugar concentration against flight distance, which
    /// is exactly what makes the waggle dance an optimisation algorithm.
    public func forageQuality(onDay day: Int, config: SimulationConfig) -> Double {
        let standing = remainingNectar + remainingPollen * 0.7
        guard standing > 0 else { return 0 }
        let richness = standing / (nectarCapacity + pollenCapacity * 0.7)
        let keystoneBonus = resolvedSpecies.isKeystone ? 1.35 : 1.0
        // Scouts weigh a thinning stand down. Without this a faded patch still
        // recruited as hard as a fresh one, and the dance stopped being the
        // optimisation it is supposed to model.
        let vigour = self.vigour(onDay: day, config: config)
        return richness * distanceEfficiency
            * resolvedSpecies.rarity.yieldMultiplier * keystoneBonus * vigour
    }

    /// Draws up to the requested amounts, returning what was actually taken.
    public mutating func harvest(nectar: Double, pollen: Double) -> (nectar: Double, pollen: Double) {
        let takenNectar = min(max(0, nectar), remainingNectar)
        let takenPollen = min(max(0, pollen), remainingPollen)
        remainingNectar -= takenNectar
        remainingPollen -= takenPollen
        return (takenNectar, takenPollen)
    }

    /// Flowers refill overnight while in bloom. Without this, the player would
    /// have to photograph continuously to keep a colony alive, which would make
    /// the game a chore rather than a habit.
    public mutating func regrow(rate: Double, onDay day: Int, config: SimulationConfig) {
        // `min` rather than a guarded add, so a patch that has faded since the
        // last regrowth is brought *down* to its new ceiling rather than
        // sitting above it holding forage that is no longer there.
        let nectarCeiling = nectarCapacity(onDay: day, config: config)
        let pollenCeiling = pollenCapacity(onDay: day, config: config)

        remainingNectar = min(nectarCeiling, remainingNectar + nectarCeiling * max(0, rate))
        remainingPollen = min(pollenCeiling, remainingPollen + pollenCeiling * max(0, rate))
    }
}
