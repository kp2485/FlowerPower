//
//  Taxonomy.swift
//  FlowerPowerCore
//
//  What a flower *is*, at whatever precision is actually known.
//
//  The game used to ask one question — "which species is this?" — and accept
//  one of two answers: a name, or nothing. That is not how identifying a plant
//  works, and it is not how a bee experiences one either.
//
//  Identification degrades by rank. A photograph may plainly be a member of
//  the daisy family without being placeable as a dandelion rather than a
//  hawkbit; it may be a *Trifolium* without being white clover rather than
//  red. Each of those is a real, useful answer, and each is worth something
//  different, because the traits that decide whether a honey bee can work a
//  flower are conserved at different ranks.
//
//  That conservation is the point. Corolla architecture is largely a family
//  trait: everything in Apiaceae is a shallow open dish, everything in
//  Plantaginaceae that looks like a foxglove is a deep tube. Nectar sugar
//  concentration varies more, by genus and species. So a family-level
//  identification genuinely tells you most of what governs access, and a
//  species-level one tells you the rest.
//
//  Families follow APG IV, which moves a few plants from where an older book
//  would put them: lime is Malvaceae rather than Tiliaceae, foxglove is
//  Plantaginaceae rather than Scrophulariaceae, and phacelia is Boraginaceae
//  rather than Hydrophyllaceae.
//

import Foundation

// MARK: - Rank

/// How precisely a plant has been placed.
///
/// Ordered, so `>=` means "at least this precise".
public enum TaxonomicRank: Int, Codable, Comparable, CaseIterable, Sendable {
    case family
    case genus
    case species

    public static func < (lhs: TaxonomicRank, rhs: TaxonomicRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .family: return "Family"
        case .genus: return "Genus"
        case .species: return "Species"
        }
    }
}

// MARK: - Families

/// The plant families a temperate honey bee colony actually forages on.
///
/// Each carries the traits its members typically share, which is what makes a
/// family-level identification useful rather than a consolation prize.
public enum PlantFamily: String, Codable, CaseIterable, Sendable {

    case asteraceae
    case fabaceae
    case rosaceae
    case brassicaceae
    case boraginaceae
    case lamiaceae
    case ericaceae
    case salicaceae
    case araliaceae
    case malvaceae
    case papaveraceae
    case plantaginaceae
    case balsaminaceae
    case berberidaceae
    case crassulaceae
    case iridaceae
    case asparagaceae
    case apiaceae

    /// The botanical name, which is the identifier a person can look up.
    public var scientificName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// What a gardener would call it.
    public var commonName: String {
        switch self {
        case .asteraceae: return "Daisy Family"
        case .fabaceae: return "Pea Family"
        case .rosaceae: return "Rose Family"
        case .brassicaceae: return "Cabbage Family"
        case .boraginaceae: return "Borage Family"
        case .lamiaceae: return "Mint Family"
        case .ericaceae: return "Heather Family"
        case .salicaceae: return "Willow Family"
        case .araliaceae: return "Ivy Family"
        case .malvaceae: return "Mallow Family"
        case .papaveraceae: return "Poppy Family"
        case .plantaginaceae: return "Plantain Family"
        case .balsaminaceae: return "Balsam Family"
        case .berberidaceae: return "Barberry Family"
        case .crassulaceae: return "Stonecrop Family"
        case .iridaceae: return "Iris Family"
        case .asparagaceae: return "Asparagus Family"
        case .apiaceae: return "Carrot Family"
        }
    }

    /// One line on what the family means to a colony, for the interface.
    public var forageNote: String {
        switch self {
        case .asteraceae:
            return "Shallow disc florets any bee can work, in enormous numbers. Pollen quality is mixed."
        case .fabaceae:
            return "Corolla depth varies hugely across the family, and decides whether a honey bee gets in at all."
        case .rosaceae:
            return "Open, shallow flowers with good pollen. The spring blossom a colony builds up on."
        case .brassicaceae:
            return "Shallow, abundant, and high in both sugar and pollen protein. Crystallises quickly in the comb."
        case .boraginaceae:
            return "Among the best nectar there is, and refills fast enough to be worth returning to."
        case .lamiaceae:
            return "Tubular and aromatic. Moderately deep, so a honey bee works them less easily than a bumblebee."
        case .ericaceae:
            return "Small bells on acid ground, flowering late when little else does."
        case .salicaceae:
            return "Catkins with exposed nectar and abundant pollen, at the moment in spring the colony needs it most."
        case .araliaceae:
            return "Utterly open nectaries, in autumn. The last major forage of the year."
        case .malvaceae:
            return "Lime flowers in high summer: heavy nectar flow over a short, unreliable window."
        case .papaveraceae:
            return "No nectar at all. Pollen only, and a great deal of it."
        case .plantaginaceae:
            return "Deep tubes built for long-tongued bumblebees. A honey bee mostly cannot reach the nectar."
        case .balsaminaceae:
            return "Long spurs, but wide enough to enter. A heavy late-summer flow where it has naturalised."
        case .berberidaceae:
            return "Winter and early spring flowers, valuable for when they open rather than how much they hold."
        case .crassulaceae:
            return "Flat heads of open flowers in autumn, easy for anything to work."
        case .iridaceae:
            return "Long perianth tubes. Worked mostly for pollen on the first warm days of the year."
        case .asparagaceae:
            return "Pendent bells on a long tube, suited to bumblebees more than honey bees."
        case .apiaceae:
            return "The shallowest flowers there are — open dishes any insect can feed from."
        }
    }

    /// Traits shared across the family, used when that is all that is known.
    ///
    /// These are typical values rather than measurements of any one plant, and
    /// the ordering between families matters far more than the third decimal
    /// place of any of them.
    public var typicalTraits: FloralTraits {
        switch self {
        case .asteraceae:
            return FloralTraits(
                corollaDepthMillimetres: 3,
                nectarSugarConcentration: 0.33,
                nectarVolume: 0.8,
                pollenProteinFraction: 0.17,
                pollenAminoAcidCompleteness: 0.75,
                pollenAbundance: 1.1
            )
        case .fabaceae:
            return FloralTraits(
                corollaDepthMillimetres: 5,
                nectarSugarConcentration: 0.38,
                nectarVolume: 1.1,
                pollenProteinFraction: 0.25,
                pollenAminoAcidCompleteness: 0.95,
                pollenAbundance: 0.8
            )
        case .rosaceae:
            return FloralTraits(
                corollaDepthMillimetres: 2,
                nectarSugarConcentration: 0.30,
                nectarVolume: 0.9,
                pollenProteinFraction: 0.21,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 1.2
            )
        case .brassicaceae:
            return FloralTraits(
                corollaDepthMillimetres: 2,
                nectarSugarConcentration: 0.45,
                nectarVolume: 1.2,
                pollenProteinFraction: 0.24,
                pollenAminoAcidCompleteness: 0.95,
                pollenAbundance: 1.2
            )
        case .boraginaceae:
            return FloralTraits(
                corollaDepthMillimetres: 5,
                nectarSugarConcentration: 0.42,
                nectarVolume: 1.6,
                pollenProteinFraction: 0.22,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 0.9
            )
        case .lamiaceae:
            return FloralTraits(
                corollaDepthMillimetres: 6,
                nectarSugarConcentration: 0.40,
                nectarVolume: 1.2,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 0.6
            )
        case .ericaceae:
            return FloralTraits(
                corollaDepthMillimetres: 3,
                nectarSugarConcentration: 0.32,
                nectarVolume: 0.7,
                pollenProteinFraction: 0.18,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 0.7
            )
        case .salicaceae:
            return FloralTraits(
                corollaDepthMillimetres: 0.5,
                nectarSugarConcentration: 0.30,
                nectarVolume: 0.6,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.95,
                pollenAbundance: 2.0
            )
        case .araliaceae:
            return FloralTraits(
                corollaDepthMillimetres: 1,
                nectarSugarConcentration: 0.49,
                nectarVolume: 1.4,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 1.1
            )
        case .malvaceae:
            return FloralTraits(
                corollaDepthMillimetres: 3,
                nectarSugarConcentration: 0.35,
                nectarVolume: 1.7,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 0.8
            )
        case .papaveraceae:
            return FloralTraits(
                corollaDepthMillimetres: 0,
                nectarSugarConcentration: 0,
                nectarVolume: 0,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 2.2,
                producesNectar: false
            )
        case .plantaginaceae:
            return FloralTraits(
                corollaDepthMillimetres: 22,
                nectarSugarConcentration: 0.38,
                nectarVolume: 1.5,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 0.9
            )
        case .balsaminaceae:
            return FloralTraits(
                corollaDepthMillimetres: 8,
                nectarSugarConcentration: 0.40,
                nectarVolume: 1.8,
                pollenProteinFraction: 0.19,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 1.4
            )
        case .berberidaceae:
            return FloralTraits(
                corollaDepthMillimetres: 4,
                nectarSugarConcentration: 0.35,
                nectarVolume: 0.8,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.9,
                pollenAbundance: 0.9
            )
        case .crassulaceae:
            return FloralTraits(
                corollaDepthMillimetres: 2,
                nectarSugarConcentration: 0.34,
                nectarVolume: 0.9,
                pollenProteinFraction: 0.18,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 0.8
            )
        case .iridaceae:
            return FloralTraits(
                corollaDepthMillimetres: 12,
                nectarSugarConcentration: 0.30,
                nectarVolume: 0.5,
                pollenProteinFraction: 0.20,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 1.6
            )
        case .asparagaceae:
            return FloralTraits(
                corollaDepthMillimetres: 10,
                nectarSugarConcentration: 0.35,
                nectarVolume: 0.9,
                pollenProteinFraction: 0.19,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 0.8
            )
        case .apiaceae:
            return FloralTraits(
                corollaDepthMillimetres: 0.5,
                nectarSugarConcentration: 0.30,
                nectarVolume: 0.5,
                pollenProteinFraction: 0.18,
                pollenAminoAcidCompleteness: 0.85,
                pollenAbundance: 1.0
            )
        }
    }
}

// MARK: - A placement

/// Where a plant sits, to whatever depth is known.
public struct Taxon: Codable, Hashable, Sendable {

    public let family: PlantFamily
    /// Capitalised, as botanical convention requires: `Trifolium`.
    public let genus: String?
    /// Lower case, as botanical convention requires: `repens`.
    public let specificEpithet: String?

    public init(family: PlantFamily, genus: String? = nil, specificEpithet: String? = nil) {
        self.family = family
        // A specific epithet without a genus is not a placement, it is half a
        // name. Dropped rather than stored, so `rank` cannot lie.
        self.genus = genus
        self.specificEpithet = genus == nil ? nil : specificEpithet
    }

    public var rank: TaxonomicRank {
        if specificEpithet != nil { return .species }
        if genus != nil { return .genus }
        return .family
    }

    /// The name as it should be written, including the conventions for a
    /// placement that stops short of a species.
    public var scientificName: String {
        switch rank {
        case .species:
            return "\(genus ?? "") \(specificEpithet ?? "")"
        case .genus:
            // "sp." is how a botanist writes "a member of this genus, species
            // undetermined". It is not a hedge, it is the correct notation.
            return "\(genus ?? "") sp."
        case .family:
            return family.scientificName
        }
    }

    /// Whether this placement is consistent with, and no more precise than,
    /// another. Used to check a coarse identification against a known plant.
    public func contains(_ other: Taxon) -> Bool {
        guard family == other.family else { return false }
        if let genus, genus != other.genus { return false }
        if let specificEpithet, specificEpithet != other.specificEpithet { return false }
        return true
    }

    /// The same plant, described less precisely.
    public func generalised(to rank: TaxonomicRank) -> Taxon {
        switch rank {
        case .family: return Taxon(family: family)
        case .genus: return Taxon(family: family, genus: genus)
        case .species: return self
        }
    }
}
