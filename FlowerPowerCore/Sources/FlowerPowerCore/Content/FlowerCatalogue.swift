//
//  FlowerCatalogue.swift
//  FlowerPowerCore
//
//  The plants the game knows about.
//
//  Values are grounded in real forage data: nectar and pollen ratings roughly
//  follow published honey-plant tables, and the bloom seasons are what actually
//  makes the photo loop interesting. A crocus photographed in August banks the
//  sighting but feeds nobody until spring, and heather is worth far more than
//  its raw yield because it blooms when the colony is provisioning for winter.
//
//  Rarity is a game concept rather than a botanical one: it tracks how
//  rewarding a find should feel, which correlates with how deliberately a
//  player has to go looking.
//

import Foundation

public enum FlowerCatalogue {

    // MARK: - Spring

    /// The first pollen of the year, when the colony has nothing else. The
    /// perianth tube is long, so it is worked for pollen far more than nectar.
    public static let crocus = FlowerSpecies(
        id: "crocus", commonName: "Crocus",
        taxon: Taxon(family: .iridaceae, genus: "Crocus", specificEpithet: "vernus"),
        rarity: .common,
        bloomSeasons: [.spring], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 12, nectarSugarConcentration: 0.3,
            nectarVolume: 0.5, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 1.8
        )
    )

    /// Catkins with exposed nectaries and enormous quantities of pollen at about
    /// 21% crude protein, arriving exactly when the colony is trying to build
    /// up. Few plants matter more to a colony's year.
    public static let willow = FlowerSpecies(
        id: "willow", commonName: "Pussy Willow",
        taxon: Taxon(family: .salicaceae, genus: "Salix", specificEpithet: "caprea"),
        rarity: .uncommon,
        bloomSeasons: [.spring], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 0.5, nectarSugarConcentration: 0.3,
            nectarVolume: 0.6, pollenProteinFraction: 0.21,
            pollenAminoAcidCompleteness: 0.95, pollenAbundance: 2.2
        )
    )

    /// Abundant, shallow, easy to work, and nutritionally poor. Dandelion pollen
    /// is measurably short of arginine, isoleucine, leucine and valine, and a
    /// colony rearing brood on it alone does badly however much it collects.
    /// The completeness figure is what carries that.
    public static let dandelion = FlowerSpecies(
        id: "dandelion", commonName: "Dandelion",
        taxon: Taxon(family: .asteraceae, genus: "Taraxacum", specificEpithet: "officinale"),
        rarity: .common,
        bloomSeasons: [.spring, .summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.32,
            nectarVolume: 1.0, pollenProteinFraction: 0.14,
            pollenAminoAcidCompleteness: 0.6, pollenAbundance: 1.6
        )
    )

    public static let appleBlossom = FlowerSpecies(
        id: "apple", commonName: "Apple Blossom",
        taxon: Taxon(family: .rosaceae, genus: "Malus", specificEpithet: "domestica"),
        rarity: .common,
        bloomSeasons: [.spring]
    )

    public static let hawthorn = FlowerSpecies(
        id: "hawthorn", commonName: "Hawthorn",
        taxon: Taxon(family: .rosaceae, genus: "Crataegus", specificEpithet: "monogyna"),
        rarity: .common,
        bloomSeasons: [.spring],
        traits: FloralTraits(
            corollaDepthMillimetres: 1.5, nectarSugarConcentration: 0.32,
            nectarVolume: 1.1, pollenProteinFraction: 0.21,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.0
        )
    )

    /// Shallow, concentrated, and effectively unlimited where it is grown. It
    /// also granulates in the comb within days, which is a real difficulty for
    /// a beekeeper and is not modelled here.
    public static let oilseedRape = FlowerSpecies(
        id: "oilseed_rape", commonName: "Oilseed Rape",
        taxon: Taxon(family: .brassicaceae, genus: "Brassica", specificEpithet: "napus"),
        rarity: .common,
        bloomSeasons: [.spring],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.48,
            nectarVolume: 1.6, pollenProteinFraction: 0.24,
            pollenAminoAcidCompleteness: 0.95, pollenAbundance: 1.3
        )
    )

    /// A pendent bell on a long tube. Bumblebees work it comfortably; a honey
    /// bee reaches only the top of the nectar.
    public static let bluebell = FlowerSpecies(
        id: "bluebell", commonName: "Bluebell",
        taxon: Taxon(family: .asparagaceae, genus: "Hyacinthoides", specificEpithet: "non-scripta"),
        rarity: .uncommon,
        bloomSeasons: [.spring],
        traits: FloralTraits(
            corollaDepthMillimetres: 10, nectarSugarConcentration: 0.35,
            nectarVolume: 0.9, pollenProteinFraction: 0.19,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 0.8
        )
    )

    public static let cherryBlossom = FlowerSpecies(
        id: "cherry", commonName: "Cherry Blossom",
        taxon: Taxon(family: .rosaceae, genus: "Prunus", specificEpithet: "avium"),
        rarity: .common,
        bloomSeasons: [.spring]
    )


    // MARK: - Summer

    /// The classic honey plant, and the reason corolla depth is modelled at all.
    /// Its tube is about 2 mm. Red clover is the same genus with comparable
    /// nectar and a 9-10 mm tube, and is famously close to useless for a honey
    /// bee. The whole difference is reach.
    public static let whiteClover = FlowerSpecies(
        id: "white_clover", commonName: "White Clover",
        taxon: Taxon(family: .fabaceae, genus: "Trifolium", specificEpithet: "repens"),
        rarity: .common,
        bloomSeasons: [.spring, .summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.35,
            nectarVolume: 1.2, pollenProteinFraction: 0.25,
            pollenAminoAcidCompleteness: 0.95, pollenAbundance: 0.9
        )
    )

    /// Refills within minutes of being emptied, which is why bees work it all day
    /// and why it out-yields plants holding far more nectar at any one moment.
    public static let borage = FlowerSpecies(
        id: "borage", commonName: "Borage",
        taxon: Taxon(family: .boraginaceae, genus: "Borago", specificEpithet: "officinalis"),
        rarity: .uncommon,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 5, nectarSugarConcentration: 0.45,
            nectarVolume: 2.0, pollenProteinFraction: 0.22,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.0
        )
    )

    public static let lavender = FlowerSpecies(
        id: "lavender", commonName: "Lavender",
        taxon: Taxon(family: .lamiaceae, genus: "Lavandula", specificEpithet: "angustifolia"),
        rarity: .common,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 6, nectarSugarConcentration: 0.4,
            nectarVolume: 1.2, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 0.6
        )
    )

    /// Open, long-flowering and everywhere. The summer mainstay.
    public static let bramble = FlowerSpecies(
        id: "bramble", commonName: "Bramble",
        taxon: Taxon(family: .rosaceae, genus: "Rubus", specificEpithet: "fruticosus"),
        rarity: .common,
        bloomSeasons: [.summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.33,
            nectarVolume: 1.4, pollenProteinFraction: 0.21,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.2
        )
    )

    /// A very heavy flow over about a fortnight, and unreliable from one year to
    /// the next. Malvaceae rather than Tiliaceae, following APG IV.
    public static let lime = FlowerSpecies(
        id: "lime", commonName: "Lime Tree",
        taxon: Taxon(family: .malvaceae, genus: "Tilia", specificEpithet: "europaea"),
        rarity: .uncommon,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 3, nectarSugarConcentration: 0.35,
            nectarVolume: 2.2, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 0.8
        )
    )

    /// Sown deliberately as a bee plant, and earns it. Boraginaceae under APG IV,
    /// where an older book would say Hydrophyllaceae.
    public static let phacelia = FlowerSpecies(
        id: "phacelia", commonName: "Phacelia",
        taxon: Taxon(family: .boraginaceae, genus: "Phacelia", specificEpithet: "tanacetifolia"),
        rarity: .uncommon,
        bloomSeasons: [.summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 4, nectarSugarConcentration: 0.42,
            nectarVolume: 1.9, pollenProteinFraction: 0.23,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.4
        )
    )

    public static let sunflower = FlowerSpecies(
        id: "sunflower", commonName: "Sunflower",
        taxon: Taxon(family: .asteraceae, genus: "Helianthus", specificEpithet: "annuus"),
        rarity: .common,
        bloomSeasons: [.summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 4, nectarSugarConcentration: 0.35,
            nectarVolume: 1.0, pollenProteinFraction: 0.16,
            pollenAminoAcidCompleteness: 0.8, pollenAbundance: 1.3
        )
    )

    /// Long florets for a composite, so a honey bee reaches the nectar but not as
    /// easily as a bumblebee does.
    public static let thistle = FlowerSpecies(
        id: "thistle", commonName: "Thistle",
        taxon: Taxon(family: .asteraceae, genus: "Cirsium", specificEpithet: "arvense"),
        rarity: .common,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 7, nectarSugarConcentration: 0.38,
            nectarVolume: 1.3, pollenProteinFraction: 0.17,
            pollenAminoAcidCompleteness: 0.8, pollenAbundance: 1.0
        )
    )

    /// A bumblebee flower. The tube is well over 20 mm, so a honey bee cannot
    /// reach the nectar however much is in there. This is the plant that
    /// `nectarAccessibility` exists to describe. Plantaginaceae under APG IV.
    public static let foxglove = FlowerSpecies(
        id: "foxglove", commonName: "Foxglove",
        taxon: Taxon(family: .plantaginaceae, genus: "Digitalis", specificEpithet: "purpurea"),
        rarity: .uncommon,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 22, nectarSugarConcentration: 0.38,
            nectarVolume: 1.5, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 0.9
        )
    )

    /// No nectar whatsoever, and pollen in vast quantity. A single richness
    /// number could not express that, and had poppies wrong in both
    /// directions at once.
    public static let poppy = FlowerSpecies(
        id: "poppy", commonName: "Poppy",
        taxon: Taxon(family: .papaveraceae, genus: "Papaver", specificEpithet: "rhoeas"),
        rarity: .common,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 0, nectarSugarConcentration: 0,
            nectarVolume: 0, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 2.4, producesNectar: false
        )
    )

    public static let echinacea = FlowerSpecies(
        id: "echinacea", commonName: "Coneflower",
        taxon: Taxon(family: .asteraceae, genus: "Echinacea", specificEpithet: "purpurea"),
        rarity: .uncommon,
        bloomSeasons: [.summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 5, nectarSugarConcentration: 0.34,
            nectarVolume: 1.1, pollenProteinFraction: 0.17,
            pollenAminoAcidCompleteness: 0.8, pollenAbundance: 0.9
        )
    )

    /// Flowers through a mild winter, which is worth far more than its yield.
    public static let rosemary = FlowerSpecies(
        id: "rosemary", commonName: "Rosemary",
        taxon: Taxon(family: .lamiaceae, genus: "Salvia", specificEpithet: "rosmarinus"),
        rarity: .common,
        bloomSeasons: [.spring, .winter], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 5, nectarSugarConcentration: 0.42,
            nectarVolume: 1.3, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 0.6
        )
    )

    /// Small accessible bells across whole moors, in late summer and autumn when
    /// the lowland has finished. The honey is thixotropic and will not spin out
    /// of the comb, which is a beekeeper's problem rather than a colony's.
    public static let heather = FlowerSpecies(
        id: "heather", commonName: "Heather",
        taxon: Taxon(family: .ericaceae, genus: "Calluna", specificEpithet: "vulgaris"),
        rarity: .uncommon,
        bloomSeasons: [.autumn], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.33,
            nectarVolume: 1.5, pollenProteinFraction: 0.18,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 0.8
        )
    )


    // MARK: - Autumn

    /// Completely open nectaries, nectar at nearly 50% sugar, and the last real
    /// forage of the year. What a colony goes into winter on.
    public static let ivy = FlowerSpecies(
        id: "ivy", commonName: "Ivy",
        taxon: Taxon(family: .araliaceae, genus: "Hedera", specificEpithet: "helix"),
        rarity: .common,
        bloomSeasons: [.autumn], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 1, nectarSugarConcentration: 0.49,
            nectarVolume: 1.5, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.2
        )
    )

    /// Invasive, and from a colony's point of view a windfall: a heavy late flow
    /// that sends foragers home dusted white.
    public static let balsam = FlowerSpecies(
        id: "balsam", commonName: "Himalayan Balsam",
        taxon: Taxon(family: .balsaminaceae, genus: "Impatiens", specificEpithet: "glandulifera"),
        rarity: .common,
        bloomSeasons: [.summer, .autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 8, nectarSugarConcentration: 0.4,
            nectarVolume: 2.0, pollenProteinFraction: 0.19,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 1.5
        )
    )

    public static let goldenrod = FlowerSpecies(
        id: "goldenrod", commonName: "Goldenrod",
        taxon: Taxon(family: .asteraceae, genus: "Solidago", specificEpithet: "virgaurea"),
        rarity: .common,
        bloomSeasons: [.autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.34,
            nectarVolume: 1.0, pollenProteinFraction: 0.17,
            pollenAminoAcidCompleteness: 0.8, pollenAbundance: 1.1
        )
    )

    public static let aster = FlowerSpecies(
        id: "aster", commonName: "Michaelmas Daisy",
        taxon: Taxon(family: .asteraceae, genus: "Symphyotrichum", specificEpithet: "novi-belgii"),
        rarity: .common,
        bloomSeasons: [.autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 3, nectarSugarConcentration: 0.33,
            nectarVolume: 0.9, pollenProteinFraction: 0.17,
            pollenAminoAcidCompleteness: 0.8, pollenAbundance: 1.0
        )
    )

    public static let sedum = FlowerSpecies(
        id: "sedum", commonName: "Ice Plant",
        taxon: Taxon(family: .crassulaceae, genus: "Hylotelephium", specificEpithet: "spectabile"),
        rarity: .common,
        bloomSeasons: [.autumn],
        traits: FloralTraits(
            corollaDepthMillimetres: 2, nectarSugarConcentration: 0.34,
            nectarVolume: 0.9, pollenProteinFraction: 0.18,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 0.8
        )
    )


    // MARK: - Winter and rarities

    /// Almost nothing flowers in winter, which is what makes this extraordinary.
    public static let winterHeather = FlowerSpecies(
        id: "winter_heather", commonName: "Winter Heather",
        taxon: Taxon(family: .ericaceae, genus: "Erica", specificEpithet: "carnea"),
        rarity: .rare,
        bloomSeasons: [.winter, .spring], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 5, nectarSugarConcentration: 0.32,
            nectarVolume: 0.9, pollenProteinFraction: 0.18,
            pollenAminoAcidCompleteness: 0.85, pollenAbundance: 0.7
        )
    )

    public static let mahonia = FlowerSpecies(
        id: "mahonia", commonName: "Mahonia",
        taxon: Taxon(family: .berberidaceae, genus: "Mahonia", specificEpithet: "aquifolium"),
        rarity: .rare,
        bloomSeasons: [.winter, .spring], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 4, nectarSugarConcentration: 0.35,
            nectarVolume: 0.9, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 0.9
        )
    )

    /// Among the highest-yielding nectar plants in Britain, and it refills as
    /// fast as borage does.
    public static let vipersBugloss = FlowerSpecies(
        id: "vipers_bugloss", commonName: "Viper's Bugloss",
        taxon: Taxon(family: .boraginaceae, genus: "Echium", specificEpithet: "vulgare"),
        rarity: .rare,
        bloomSeasons: [.summer, .autumn], isKeystone: true,
        traits: FloralTraits(
            corollaDepthMillimetres: 5, nectarSugarConcentration: 0.45,
            nectarVolume: 2.4, pollenProteinFraction: 0.22,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.0
        )
    )

    /// Nectarless, like the poppy, and visited only for pollen. The scent
    /// suggests otherwise, which is exactly why it is worth modelling.
    public static let meadowsweet = FlowerSpecies(
        id: "meadowsweet", commonName: "Meadowsweet",
        taxon: Taxon(family: .rosaceae, genus: "Filipendula", specificEpithet: "ulmaria"),
        rarity: .rare,
        bloomSeasons: [.summer],
        traits: FloralTraits(
            corollaDepthMillimetres: 0, nectarSugarConcentration: 0,
            nectarVolume: 0, pollenProteinFraction: 0.2,
            pollenAminoAcidCompleteness: 0.9, pollenAbundance: 1.9, producesNectar: false
        )
    )
    // MARK: - Lookup

    public static let all: [FlowerSpecies] = [
        crocus, willow, dandelion, appleBlossom, hawthorn, oilseedRape, bluebell, cherryBlossom,
        whiteClover, borage, lavender, bramble, lime, phacelia, sunflower, thistle, foxglove,
        poppy, echinacea, rosemary,
        heather, ivy, balsam, goldenrod, aster, sedum,
        winterHeather, mahonia, vipersBugloss, meadowsweet
    ]

    private static let index: [String: FlowerSpecies] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// Looks up a species by the identifier a classifier emitted.
    public static func species(withID id: String) -> FlowerSpecies? {
        index[id]
    }

    /// Species in bloom during a given season, best nectar first — the list to
    /// show a player wondering what is worth going out to photograph.
    public static func inBloom(during season: Season) -> [FlowerSpecies] {
        all
            .filter { $0.isInBloom(during: season) }
            .sorted { $0.nectarRichness > $1.nectarRichness }
    }

    /// Plants that flower when little else does. These are what carry a colony
    /// through the gaps, and are worth telling the player about.
    public static func keystones(for season: Season) -> [FlowerSpecies] {
        inBloom(during: season).filter(\.isKeystone)
    }

    /// Best-effort match for a free-text label, for classifiers whose output
    /// does not use our identifiers.
    ///
    /// Tried in descending order of confidence, and it stops at the first
    /// answer rather than scoring: an exact identifier, an exact name, a known
    /// synonym, and only then a phrase inside a longer label. See
    /// `ClassifierLabels` for why the last of those is fussier than it looks.
    public static func match(label: String) -> FlowerSpecies? {
        let needle = ClassifierLabels.normalise(label)
        guard !needle.isEmpty else { return nil }

        // Our own identifier, as `white_clover` or `white clover`.
        if let exact = index[needle.replacingOccurrences(of: " ", with: "_")] {
            return exact
        }

        // An exact common or scientific name.
        if let exact = all.first(where: { species in
            ClassifierLabels.normalise(species.commonName) == needle
                || species.scientificName.map { ClassifierLabels.normalise($0) == needle } == true
        }) {
            return exact
        }

        // A known synonym from another vocabulary.
        if let id = ClassifierLabels.index[needle], let species = index[id] {
            return species
        }

        // A name sitting inside a longer label — "purple coneflower echinacea
        // purpurea", say, or a dataset that prefixes a family. Whole words
        // only, and only for phrases specific enough to be worth trusting.
        let candidates: [(phrase: String, id: String)] =
            ClassifierLabels.aliases.flatMap { id, names in
                names.map { (ClassifierLabels.normalise($0), id) }
            }
            + all.map { (ClassifierLabels.normalise($0.commonName), $0.id) }

        // Longest first, so "winter heath" is preferred over "heath" and a
        // more specific reading always wins.
        let match = candidates
            .filter { $0.phrase.components(separatedBy: " ").count
                >= ClassifierLabels.minimumWordsForPhraseMatch }
            .sorted { $0.phrase.count > $1.phrase.count }
            .first { ClassifierLabels.containsWholePhrase($0.phrase, in: needle) }

        return match.flatMap { index[$0.id] }
    }
}
