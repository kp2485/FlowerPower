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

    public static let crocus = FlowerSpecies(
        id: "crocus", commonName: "Crocus", scientificName: "Crocus vernus",
        rarity: .common, nectarRichness: 0.7, pollenRichness: 1.5,
        bloomSeasons: [.spring],
        // The first pollen of the year, when the colony has nothing else.
        isKeystone: true
    )

    public static let willow = FlowerSpecies(
        id: "willow", commonName: "Pussy Willow", scientificName: "Salix caprea",
        rarity: .uncommon, nectarRichness: 0.9, pollenRichness: 1.9,
        bloomSeasons: [.spring], isKeystone: true
    )

    public static let dandelion = FlowerSpecies(
        id: "dandelion", commonName: "Dandelion", scientificName: "Taraxacum officinale",
        rarity: .common, nectarRichness: 1.1, pollenRichness: 1.4,
        bloomSeasons: [.spring, .summer]
    )

    public static let appleBlossom = FlowerSpecies(
        id: "apple", commonName: "Apple Blossom", scientificName: "Malus domestica",
        rarity: .common, nectarRichness: 1.2, pollenRichness: 1.1,
        bloomSeasons: [.spring]
    )

    public static let hawthorn = FlowerSpecies(
        id: "hawthorn", commonName: "Hawthorn", scientificName: "Crataegus monogyna",
        rarity: .common, nectarRichness: 1.3, pollenRichness: 0.9,
        bloomSeasons: [.spring]
    )

    public static let oilseedRape = FlowerSpecies(
        id: "oilseed_rape", commonName: "Oilseed Rape", scientificName: "Brassica napus",
        rarity: .common, nectarRichness: 1.9, pollenRichness: 1.5,
        bloomSeasons: [.spring]
    )

    public static let bluebell = FlowerSpecies(
        id: "bluebell", commonName: "Bluebell", scientificName: "Hyacinthoides non-scripta",
        rarity: .uncommon, nectarRichness: 1.0, pollenRichness: 0.7,
        bloomSeasons: [.spring]
    )

    public static let cherryBlossom = FlowerSpecies(
        id: "cherry", commonName: "Cherry Blossom", scientificName: "Prunus avium",
        rarity: .common, nectarRichness: 1.1, pollenRichness: 1.2,
        bloomSeasons: [.spring]
    )

    // MARK: - Summer

    public static let whiteClover = FlowerSpecies(
        id: "white_clover", commonName: "White Clover", scientificName: "Trifolium repens",
        rarity: .common, nectarRichness: 1.4, pollenRichness: 1.0,
        bloomSeasons: [.spring, .summer, .autumn]
    )

    public static let borage = FlowerSpecies(
        id: "borage", commonName: "Borage", scientificName: "Borago officinalis",
        rarity: .uncommon, nectarRichness: 2.0, pollenRichness: 1.0,
        bloomSeasons: [.summer, .autumn]
    )

    public static let lavender = FlowerSpecies(
        id: "lavender", commonName: "Lavender", scientificName: "Lavandula angustifolia",
        rarity: .common, nectarRichness: 1.5, pollenRichness: 0.6,
        bloomSeasons: [.summer]
    )

    public static let bramble = FlowerSpecies(
        id: "bramble", commonName: "Bramble", scientificName: "Rubus fruticosus",
        rarity: .common, nectarRichness: 1.5, pollenRichness: 1.1,
        bloomSeasons: [.summer, .autumn]
    )

    public static let lime = FlowerSpecies(
        id: "lime", commonName: "Lime Tree", scientificName: "Tilia europaea",
        rarity: .uncommon, nectarRichness: 2.1, pollenRichness: 0.8,
        bloomSeasons: [.summer]
    )

    public static let phacelia = FlowerSpecies(
        id: "phacelia", commonName: "Phacelia", scientificName: "Phacelia tanacetifolia",
        rarity: .uncommon, nectarRichness: 1.9, pollenRichness: 1.6,
        bloomSeasons: [.summer, .autumn]
    )

    public static let sunflower = FlowerSpecies(
        id: "sunflower", commonName: "Sunflower", scientificName: "Helianthus annuus",
        rarity: .common, nectarRichness: 1.2, pollenRichness: 1.8,
        bloomSeasons: [.summer, .autumn]
    )

    public static let thistle = FlowerSpecies(
        id: "thistle", commonName: "Thistle", scientificName: "Cirsium arvense",
        rarity: .common, nectarRichness: 1.4, pollenRichness: 0.9,
        bloomSeasons: [.summer, .autumn]
    )

    public static let foxglove = FlowerSpecies(
        id: "foxglove", commonName: "Foxglove", scientificName: "Digitalis purpurea",
        rarity: .uncommon, nectarRichness: 1.3, pollenRichness: 0.8,
        bloomSeasons: [.summer]
    )

    public static let poppy = FlowerSpecies(
        id: "poppy", commonName: "Poppy", scientificName: "Papaver rhoeas",
        // Poppies offer pollen only — no nectar at all.
        rarity: .common, nectarRichness: 0.0, pollenRichness: 1.7,
        bloomSeasons: [.summer]
    )

    public static let echinacea = FlowerSpecies(
        id: "echinacea", commonName: "Coneflower", scientificName: "Echinacea purpurea",
        rarity: .common, nectarRichness: 1.2, pollenRichness: 1.0,
        bloomSeasons: [.summer, .autumn]
    )

    public static let rosemary = FlowerSpecies(
        id: "rosemary", commonName: "Rosemary", scientificName: "Salvia rosmarinus",
        rarity: .common, nectarRichness: 1.4, pollenRichness: 0.7,
        bloomSeasons: [.spring, .summer]
    )

    // MARK: - Autumn

    public static let heather = FlowerSpecies(
        id: "heather", commonName: "Heather", scientificName: "Calluna vulgaris",
        rarity: .uncommon, nectarRichness: 1.7, pollenRichness: 0.9,
        bloomSeasons: [.autumn], isKeystone: true
    )

    public static let ivy = FlowerSpecies(
        id: "ivy", commonName: "Ivy", scientificName: "Hedera helix",
        rarity: .common, nectarRichness: 1.6, pollenRichness: 1.4,
        // The last real forage of the year, and what many colonies winter on.
        bloomSeasons: [.autumn], isKeystone: true
    )

    public static let himalayanBalsam = FlowerSpecies(
        id: "balsam", commonName: "Himalayan Balsam", scientificName: "Impatiens glandulifera",
        rarity: .common, nectarRichness: 1.8, pollenRichness: 1.0,
        bloomSeasons: [.autumn]
    )

    public static let goldenrod = FlowerSpecies(
        id: "goldenrod", commonName: "Goldenrod", scientificName: "Solidago virgaurea",
        rarity: .common, nectarRichness: 1.4, pollenRichness: 1.5,
        bloomSeasons: [.autumn], isKeystone: true
    )

    public static let aster = FlowerSpecies(
        id: "aster", commonName: "Michaelmas Daisy", scientificName: "Symphyotrichum novi-belgii",
        rarity: .common, nectarRichness: 1.2, pollenRichness: 1.1,
        bloomSeasons: [.autumn]
    )

    public static let sedum = FlowerSpecies(
        id: "sedum", commonName: "Ice Plant", scientificName: "Hylotelephium spectabile",
        rarity: .common, nectarRichness: 1.3, pollenRichness: 0.9,
        bloomSeasons: [.autumn]
    )

    // MARK: - Winter and rarities

    public static let winterHeather = FlowerSpecies(
        id: "winter_heather", commonName: "Winter Heather", scientificName: "Erica carnea",
        rarity: .rare, nectarRichness: 1.1, pollenRichness: 1.0,
        // Almost nothing flowers in winter, which makes this extraordinary.
        bloomSeasons: [.winter, .spring], isKeystone: true
    )

    public static let mahonia = FlowerSpecies(
        id: "mahonia", commonName: "Mahonia", scientificName: "Mahonia aquifolium",
        rarity: .rare, nectarRichness: 1.3, pollenRichness: 1.2,
        bloomSeasons: [.winter, .spring], isKeystone: true
    )

    public static let vipersBugloss = FlowerSpecies(
        id: "vipers_bugloss", commonName: "Viper's Bugloss", scientificName: "Echium vulgare",
        rarity: .rare, nectarRichness: 2.4, pollenRichness: 1.3,
        bloomSeasons: [.summer, .autumn], isKeystone: true
    )

    public static let meadowsweet = FlowerSpecies(
        id: "meadowsweet", commonName: "Meadowsweet", scientificName: "Filipendula ulmaria",
        rarity: .rare, nectarRichness: 0.9, pollenRichness: 1.8,
        bloomSeasons: [.summer]
    )

    // MARK: - Lookup

    public static let all: [FlowerSpecies] = [
        crocus, willow, dandelion, appleBlossom, hawthorn, oilseedRape, bluebell, cherryBlossom,
        whiteClover, borage, lavender, bramble, lime, phacelia, sunflower, thistle, foxglove,
        poppy, echinacea, rosemary,
        heather, ivy, himalayanBalsam, goldenrod, aster, sedum,
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
    public static func match(label: String) -> FlowerSpecies? {
        let needle = label
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let exact = index[needle.replacingOccurrences(of: " ", with: "_")] {
            return exact
        }

        return all.first { species in
            let common = species.commonName.lowercased()
            let scientific = species.scientificName?.lowercased() ?? ""
            return common == needle
                || scientific == needle
                || common.contains(needle)
                || needle.contains(common)
        }
    }
}
