//
//  BotanyCollection.swift
//  FlowerPowerGame
//
//  The garden as a collection.
//
//  Now that flowers are placed by family, the garden implies a collection:
//  fourteen families of eighteen, which genera, how much of the bloom calendar
//  is covered. The gaps are the gentlest possible nudge to go outside — not a
//  task, just a shelf with a space on it.
//
//  Pure arithmetic over the snapshot, so it is tested here and rendered
//  wherever.
//

import Foundation
import FlowerPowerCore

public struct BotanyCollection: Equatable, Sendable {

    public struct FamilyEntry: Equatable, Identifiable, Sendable {
        /// Any family at all: the eighteen the game models, and whatever else
        /// the identifier has placed a photograph in. An orchid in the garden
        /// is listed as Orchidaceae, with a note on why the bees ignore it.
        public let family: BotanicalFamily
        public let genera: Set<String>
        /// Catalogue species identified to species rank.
        public let speciesIDs: Set<String>
        public let patchCount: Int
        public let inBloomCount: Int
        /// The finest rank any patch in this family reached.
        public let bestRank: TaxonomicRank

        public var id: BotanicalFamily { family }

        /// Whether this is one of the families the collection counts.
        public var isModelled: Bool { family.known != nil }
    }

    public let families: [FamilyEntry]
    public let missingFamilies: [PlantFamily]
    /// Which seasons have at least one patch whose plant blooms then.
    public let seasonsCovered: Set<Season>
    /// Catalogue species the player has photographed, to species rank.
    public let speciesCollected: Set<String>

    public init(patches: [PatchSummary]) {
        var byFamily: [BotanicalFamily: [PatchSummary]] = [:]
        for patch in patches {
            guard let family = patch.family else { continue }
            byFamily[family, default: []].append(patch)
        }

        var entries: [FamilyEntry] = []
        var seasons = Set<Season>()
        var species = Set<String>()

        for (family, members) in byFamily {
            var genera = Set<String>()
            var speciesIDs = Set<String>()
            var best = TaxonomicRank.family

            for patch in members {
                guard let taxon = patch.taxon else { continue }
                if let genus = taxon.genus { genera.insert(genus) }
                best = max(best, taxon.rank)

                if taxon.rank == .species,
                   let known = FlowerCatalogue.all.first(where: { $0.taxon == taxon }) {
                    speciesIDs.insert(known.id)
                    species.insert(known.id)
                    seasons.formUnion(known.bloomSeasons)
                } else {
                    seasons.formUnion(FlowerSpecies.generic(for: taxon).bloomSeasons)
                }
            }

            entries.append(FamilyEntry(
                family: family,
                genera: genera,
                speciesIDs: speciesIDs,
                patchCount: members.count,
                inBloomCount: members.filter(\.isInBloom).count,
                bestRank: best
            ))
        }

        families = entries.sorted { $0.family.scientificName < $1.family.scientificName }
        missingFamilies = PlantFamily.allCases
            .filter { byFamily[BotanicalFamily($0)] == nil }
            .sorted { $0.scientificName < $1.scientificName }
        seasonsCovered = seasons
        speciesCollected = species
    }

    /// Modelled families found, out of `familiesTotal`. Families beyond the
    /// catalogue are listed but not counted: the collection is the eighteen.
    public var familiesSeen: Int { families.filter(\.isModelled).count }
    public var familiesTotal: Int { PlantFamily.allCases.count }
    /// Families the identifier has placed a flower in that the catalogue does
    /// not model. Real botany, outside the game's own list.
    public var familiesBeyondCatalogue: [FamilyEntry] { families.filter { !$0.isModelled } }
    public var speciesTotal: Int { FlowerCatalogue.all.count }

    /// 0...1, how much of the year the garden has something for.
    public var calendarCoverage: Double {
        Double(seasonsCovered.count) / Double(Season.allCases.count)
    }

    public var seasonsMissing: [Season] {
        Season.allCases.filter { !seasonsCovered.contains($0) }
    }

    /// Catalogue species not yet photographed, best forage first — what a
    /// player wondering what to look for should be shown.
    public var speciesMissing: [FlowerSpecies] {
        FlowerCatalogue.all
            .filter { !speciesCollected.contains($0.id) }
            .sorted { $0.nectarRichness + $0.pollenRichness > $1.nectarRichness + $1.pollenRichness }
    }

    /// One line for the garden's header.
    public var summary: String {
        "\(familiesSeen) of \(familiesTotal) families · \(speciesCollected.count) of \(speciesTotal) species"
    }
}
