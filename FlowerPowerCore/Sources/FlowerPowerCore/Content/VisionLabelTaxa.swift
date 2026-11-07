//
//  VisionLabelTaxa.swift
//  FlowerPowerCore
//
//  What the operating system's own image classifier can name.
//
//  Vision's built-in `ClassifyImageRequest` ships with iOS, needs no model,
//  and knows about thirteen hundred things — among them a couple of dozen
//  flowers, the well-known ones: rose, tulip, orchid, lily, daisy, dahlia,
//  carnation, daffodil. The app has always run it, as the "is this a plant at
//  all?" gate, and then thrown the rest of its answer away. This table keeps
//  it.
//
//  It is a coarse identifier and an honest one: "tulip" is a genus, not a
//  species, and "daisy" or "marigold" is only a family, because several
//  unrelated garden plants go by each name. Each label maps to the finest
//  rank it can truthfully support. Where the catalogue has the plant —
//  sunflower, dandelion, rosemary — it maps to the catalogue entry, so the
//  colony gets the measured traits rather than the family's typical ones.
//
//  Kept in the package rather than the app so the mapping is tested on every
//  platform the engine builds on, and so a mistake here is a failing test and
//  not a bee working the wrong flower.
//

import Foundation

public enum VisionLabelTaxa {

    /// Where a label lands.
    public enum Target: Equatable, Sendable {
        /// A species the catalogue has, by its identifier.
        case catalogue(String)
        /// A placement at whatever rank the label supports.
        case taxon(Taxon)
    }

    /// The label as Vision spells it — lower case, underscores — to what it
    /// means botanically.
    public static let table: [String: Target] = [
        "rose": .taxon(Taxon(family: .rosaceae, genus: "Rosa")),
        "tulip": .taxon(Taxon(family: BotanicalFamily("liliaceae"), genus: "Tulipa")),
        "lily": .taxon(Taxon(family: BotanicalFamily("liliaceae"), genus: "Lilium")),
        "orchid": .taxon(Taxon(family: BotanicalFamily("orchidaceae"))),
        "daisy": .taxon(Taxon(family: .asteraceae)),
        "sunflower": .catalogue("sunflower"),
        "dandelion": .catalogue("dandelion"),
        "dahlia": .taxon(Taxon(family: .asteraceae, genus: "Dahlia")),
        "carnation": .taxon(Taxon(family: BotanicalFamily("caryophyllaceae"), genus: "Dianthus")),
        "daffodil": .taxon(Taxon(family: BotanicalFamily("amaryllidaceae"), genus: "Narcissus")),
        "chrysanthemum": .taxon(Taxon(family: .asteraceae, genus: "Chrysanthemum")),
        "marigold": .taxon(Taxon(family: .asteraceae)),
        "petunia": .taxon(Taxon(family: BotanicalFamily("solanaceae"), genus: "Petunia")),
        "begonia": .taxon(Taxon(family: BotanicalFamily("begoniaceae"), genus: "Begonia")),
        "snapdragon": .taxon(Taxon(family: .plantaginaceae, genus: "Antirrhinum")),
        "cornflower": .taxon(Taxon(family: .asteraceae, genus: "Centaurea", specificEpithet: "cyanus")),
        "clover": .taxon(Taxon(family: .fabaceae, genus: "Trifolium")),
        "rosemary": .catalogue("rosemary"),
        "cactus": .taxon(Taxon(family: BotanicalFamily("cactaceae")))
    ]

    /// The species a label resolves to, with its taxon, or nil for a label
    /// that is not a flower this table knows.
    public static func species(forLabel label: String) -> FlowerSpecies? {
        guard let target = table[label.lowercased()] else { return nil }
        switch target {
        case .catalogue(let id):
            return FlowerCatalogue.species(withID: id)
        case .taxon(let taxon):
            return FlowerCatalogue.all.first { $0.taxon == taxon }
                ?? FlowerSpecies.generic(for: taxon)
        }
    }

    /// Whether Vision's label is one this table can place.
    public static func knows(_ label: String) -> Bool {
        table[label.lowercased()] != nil
    }
}
