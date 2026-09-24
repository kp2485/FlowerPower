//
//  Flower.swift
//  FlowerPowerCore
//
//  Photographed flowers are the game's only source of forage. Identification
//  is a bonus: an unrecognised flower still feeds the hive, at generic yield,
//  so a poor photo degrades the reward instead of breaking the loop.
//

import Foundation

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

    /// Decoded by hand for the reason `World.init(from:)` gives: a key this
    /// build writes and an older save does not have must not make the save
    /// unreadable. A whole species is written into every patch, so this type
    /// is in every save many times over.
    ///
    /// `taxon` and `traits` are the two that have arrived since the first
    /// save, on 2026-09-06, when forage started coming from real floral traits
    /// rather than a hand-chosen richness. A species saved before then is
    /// given the catalogue's description of the plant with that id — which is
    /// what the id meant when it was written — and failing that the same
    /// family-typical estimate `init` falls back on. The richness numbers it
    /// was saved with are ignored rather than translated; they were the model
    /// that the traits replaced.
    ///
    /// Only `init(from:)` is written out; the encoder is still synthesised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        commonName = try container.decode(String.self, forKey: .commonName)
        rarity = try container.decode(FlowerRarity.self, forKey: .rarity)
        bloomSeasons = try container.decode(Set<Season>.self, forKey: .bloomSeasons)
        isKeystone = try container.decode(Bool.self, forKey: .isKeystone)

        let catalogued = FlowerCatalogue.species(withID: id)
        taxon = try container.decodeIfPresent(Taxon.self, forKey: .taxon)
            ?? catalogued?.taxon
            ?? Self.unidentified.taxon
        traits = try container.decodeIfPresent(FloralTraits.self, forKey: .traits)
            ?? catalogued?.traits
            ?? taxon.family.typicalTraits
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
    /// Nobody put it there. It grows in a cell of the country the bees have
    /// found, it is shared with every other pollinator in the parish, and it
    /// never fades — the hedge is cut and grows back, and no photograph of it
    /// is ageing.
    case wild
}

/// One photographed flower, which becomes a depleting forage patch.
public struct FlowerPatch: Identifiable, Codable, Equatable, Sendable {

    public let id: EntityID

    /// Local photo library identifier. The image itself never enters the
    /// simulation — the engine stays free of any platform image type.
    public let photoLocalIdentifier: String

    /// `nil` until classification runs; falls back to `.unidentified`.
    public var species: FlowerSpecies?

    /// Classifier confidence in 0...1, which scales the patch's yield.
    public var identificationConfidence: Double

    /// How far the bees must fly to work it, in metres. Every patch stands at
    /// the nominal distance unless a caller says otherwise, which is what makes
    /// the flower itself — its species, its richness, how much is left — the
    /// thing that decides whether working it is worth the trip.
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

    /// Where on the ground this patch stands, when it stands anywhere.
    ///
    /// Optional for the same reason as `registeredOnDay` and `storedOrigin`:
    /// every patch photographed before the world existed was nowhere in
    /// particular, and a missing cell means exactly that rather than being an
    /// error. An optional travels in both directions — an old save decodes it
    /// as nil, and a save written with one opens in a build that has never
    /// heard of it.
    ///
    /// When a patch has a cell, `distanceMetres` is derived from it and the
    /// two are kept in step by `Simulation.plant(_:at:)`. When it has none,
    /// the distance is whatever it was given.
    public var cell: HexCoordinate?

    public var origin: PatchOrigin { storedOrigin ?? .photographed }
    public var isShared: Bool { origin == .shared }

    /// Grew there on its own. No photograph stands behind it, which is why
    /// `photoLocalIdentifier` carries a sentinel rather than a library id and
    /// why nothing in the app should try to load an image for one.
    public var isWild: Bool { origin == .wild }

    /// What a wild patch's `photoLocalIdentifier` starts with.
    ///
    /// A sentinel rather than an empty string so the app can tell "there is no
    /// photograph of this, it is a hedge" from "the photograph has gone
    /// missing from the library", which are two different things to draw. The
    /// rest of the string is the cell, so it is unique and legible in a log.
    public static let wildPhotoPrefix = "wild:"

    /// The sentinel for a wild patch in a particular cell.
    public static func wildPhotoIdentifier(for cell: HexCoordinate) -> String {
        "\(wildPhotoPrefix)\(cell.q),\(cell.r)"
    }

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
        distanceMetres: Double = FlowerPatch.nominalDistance,
        discoveredAt: Date,
        registeredOnDay: Int? = nil,
        origin: PatchOrigin = .photographed,
        sharedBy: String? = nil,
        capacityScale: Double = 1,
        cell: HexCoordinate? = nil
    ) {
        self.id = id
        self.photoLocalIdentifier = photoLocalIdentifier
        self.species = species
        self.identificationConfidence = identificationConfidence
        self.distanceMetres = max(0, distanceMetres)
        self.discoveredAt = discoveredAt
        self.registeredOnDay = registeredOnDay
        self.storedOrigin = origin
        self.sharedBy = sharedBy
        self.cell = cell
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

    /// Decoded by hand for the reason `World.init(from:)` gives.
    ///
    /// Everything this type has gained since the first save — the day it was
    /// registered, where it came from, who sent it, where it stands — is
    /// optional, so the synthesised decoder happened to cope. Written out
    /// anyway because this is the type likeliest to gain the next field, and a
    /// field with a default is exactly the one synthesis does not handle: the
    /// next addition should be one more `decodeIfPresent` line here, not a
    /// save that fails to open.
    ///
    /// Only `init(from:)` is written out; the encoder is still synthesised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // In every save ever written.
        id = try container.decode(EntityID.self, forKey: .id)
        photoLocalIdentifier = try container.decode(String.self, forKey: .photoLocalIdentifier)
        species = try container.decodeIfPresent(FlowerSpecies.self, forKey: .species)
        identificationConfidence = try container.decode(
            Double.self, forKey: .identificationConfidence
        )
        distanceMetres = try container.decode(Double.self, forKey: .distanceMetres)
        discoveredAt = try container.decode(Date.self, forKey: .discoveredAt)
        remainingNectar = try container.decode(Double.self, forKey: .remainingNectar)
        remainingPollen = try container.decode(Double.self, forKey: .remainingPollen)
        nectarCapacity = try container.decode(Double.self, forKey: .nectarCapacity)
        pollenCapacity = try container.decode(Double.self, forKey: .pollenCapacity)
        recruitedForagers = try container.decode(Int.self, forKey: .recruitedForagers)

        // Arrived later, and nil is what an older save means by leaving them
        // out. See each property for what nil stands for.
        registeredOnDay = try container.decodeIfPresent(Int.self, forKey: .registeredOnDay)
        storedOrigin = try container.decodeIfPresent(PatchOrigin.self, forKey: .storedOrigin)
        sharedBy = try container.decodeIfPresent(String.self, forKey: .sharedBy)
        cell = try container.decodeIfPresent(HexCoordinate.self, forKey: .cell)
    }

    /// Total forage a plain common flower holds when full.
    public static let baseCapacity: Double = 120

    /// The distance every patch stands at unless a caller says otherwise: a
    /// middling flight, neither next to the nest nor at the edge of the range.
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
    ///
    /// **This is a *profitability*, not an amount**, and deliberately so. A
    /// dancer signals how good the source was — the sugar in it, how far she
    /// flew — and says nothing about how many bees it could feed. How many it
    /// can feed is settled where it belongs, in `ForagingSystem`: a patch
    /// gives what it has, and the foragers it cannot serve follow the next
    /// dance. Weighting the dance by the standing crop instead was tried and
    /// measured, and it cost the world-off colony twenty-eight points of
    /// two-year survival by concentrating the force on the richest species
    /// until it was stripped.
    /// Distance counts for more here than it does in the harvest — see
    /// `SimulationConfig.danceDistanceExponent`. At the default of one the
    /// two are the same slope and this is arithmetically the line it always
    /// was, skipping the `pow` rather than raising to the first power so that
    /// nothing can move in the last bit.
    public func forageQuality(onDay day: Int, config: SimulationConfig) -> Double {
        let standing = remainingNectar + remainingPollen * 0.7
        guard standing > 0 else { return 0 }
        let richness = standing / (nectarCapacity + pollenCapacity * 0.7)
        let keystoneBonus = resolvedSpecies.isKeystone ? 1.35 : 1.0
        // Scouts weigh a thinning stand down. Without this a faded patch still
        // recruited as hard as a fresh one, and the dance stopped being the
        // optimisation it is supposed to model.
        let vigour = self.vigour(onDay: day, config: config)

        let reach = config.danceDistanceExponent == 1
            ? distanceEfficiency
            : pow(distanceEfficiency, config.danceDistanceExponent)

        return richness * reach
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
