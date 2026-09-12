//
//  FieldGuide.swift
//  FlowerPowerGame
//
//  The whole catalogue, whether or not the player has found it.
//
//  `BotanyCollection` is the shelf with spaces on it: what the garden holds,
//  which families are missing, how much of the year is covered. This is the
//  other half of the same idea and the more useful one for somebody about to
//  put their boots on — every plant the game knows, what it looks like, when
//  it flowers, and whether a honey bee can work it. The collection is what the
//  player *has*; the guide is *everything*.
//
//  Nothing here is new science. Every number comes from the catalogue and
//  `FloralTraits`, and the one fact that is not botanical — whether this player
//  has photographed the plant — is read off the patches through
//  `BotanyCollection`, so the guide and the collection can never disagree
//  about what has been found.
//
//  What is new is the identification note: one sentence per species on what to
//  look for and where. A guide that lists a plant's nectar sugar and says
//  nothing about its petals is not a field guide, and the player is being asked
//  to find these things in a hedgerow rather than in a menu.
//

import Foundation
import FlowerPowerCore

// MARK: - Whether she can reach it

/// How a honey bee fares against a corolla, as a verdict rather than a number.
///
/// `FloralTraits.nectarAccessibility` already answers this in the continuous
/// form the engine needs. This is the four answers a person wants: no nectar,
/// comfortably in reach, just past it, or a flower for a different insect
/// altogether. It exists so the guide's list rows and badges say the same thing
/// the flower's own page says, out of one definition.
public enum NectarReach: String, Codable, CaseIterable, Sendable {

    /// The plant offers none at all. Poppy and meadowsweet: pollen only.
    case nectarless
    /// Within a honey bee's reach of a little under 8 mm.
    case withinReach
    /// Past her reach, but close enough that a full flower still gives
    /// something up.
    case atTheLimit
    /// A bumblebee flower. Foxglove holds a great deal of nectar that this
    /// colony will never see.
    case outOfReach

    public init(_ traits: FloralTraits) {
        guard traits.producesNectar else {
            self = .nectarless
            return
        }
        if traits.isOutOfReach {
            self = .outOfReach
        } else if traits.nectarAccessibility >= 1 {
            self = .withinReach
        } else {
            self = .atTheLimit
        }
    }

    /// Two or three words, for a badge in a list.
    public var displayName: String {
        switch self {
        case .nectarless: return "No Nectar"
        case .withinReach: return "Within Reach"
        case .atTheLimit: return "At the Limit"
        case .outOfReach: return "Out of Reach"
        }
    }

    /// A sentence, for the flower's page.
    public var detail: String {
        let reach = String(format: "%.1f", BeeMorphology.nectarReachMillimetres)
        switch self {
        case .nectarless:
            return "This plant makes no nectar. Your bees work it for pollen, and that is the whole of it."
        case .withinReach:
            return "Well inside a honey bee's reach of about \(reach) mm, so she takes what the flower offers."
        case .atTheLimit:
            return "Just past a honey bee's reach of about \(reach) mm. She gets some when the flower is full and the nectar stands high in the tube, and little otherwise."
        case .outOfReach:
            return "Deeper than a honey bee can reach. A bumblebee flower: yours can rob it at best, and mostly do not bother."
        }
    }

    /// Whether the colony can bank nectar from this flower at all.
    public var isWorkable: Bool { self == .withinReach || self == .atTheLimit }
}

// MARK: - The bloom calendar

/// Which months a season covers, and what to call them.
///
/// The seasons are asked of `RealSeason` rather than written out a second
/// time. The calendar strip on a flower's page and the prompt that says what is
/// out now must never disagree about when spring is, and the only way to
/// guarantee that is for both to read the same definition.
public enum BloomCalendar {

    public static func season(ofMonth month: Int, in hemisphere: Hemisphere) -> Season {
        var components = DateComponents()
        components.year = 2001
        components.month = min(12, max(1, month))
        // The middle of the month, so no time zone can nudge the date into a
        // neighbouring one.
        components.day = 15

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return .spring }
        return RealSeason.current(on: date, in: hemisphere, calendar: calendar)
    }

    /// Months, 1...12, in which a season falls for this hemisphere.
    public static func months(of season: Season, in hemisphere: Hemisphere) -> [Int] {
        (1...12).filter { self.season(ofMonth: $0, in: hemisphere) == season }
    }

    /// English month names. The game's copy is English throughout, and a
    /// locale-formatted month would be the only translated word on the page.
    public static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    public static func monthName(_ month: Int) -> String {
        monthNames[min(12, max(1, month)) - 1]
    }

    /// The single letter a calendar strip is labelled with.
    public static func monthInitial(_ month: Int) -> String {
        String(monthName(month).prefix(1))
    }
}

// MARK: - An entry

/// One species, as a guide describes it.
///
/// Everything except `fieldNote` and `hasBeenPhotographed` is read straight
/// through to the catalogue entry, deliberately: a guide that copied the
/// numbers would be a second set of numbers to keep in step.
public struct FieldGuideEntry: Identifiable, Equatable, Sendable {

    public let species: FlowerSpecies
    /// What to look for, and where. See `FieldGuide.fieldNotes`.
    public let fieldNote: String
    /// Whether this player has photographed it, to species rank.
    public let hasBeenPhotographed: Bool

    public init(species: FlowerSpecies, fieldNote: String, hasBeenPhotographed: Bool) {
        self.species = species
        self.fieldNote = fieldNote
        self.hasBeenPhotographed = hasBeenPhotographed
    }

    public var id: String { species.id }

    // MARK: What it is

    public var commonName: String { species.commonName }
    public var taxon: Taxon { species.taxon }
    public var family: PlantFamily { species.family }
    public var genus: String? { species.taxon.genus }
    /// "Trifolium repens", written as a botanist writes it.
    public var scientificName: String { species.taxon.scientificName }
    public var rarity: FlowerRarity { species.rarity }
    public var isKeystone: Bool { species.isKeystone }

    // MARK: What it offers

    public var traits: FloralTraits { species.traits }
    public var producesNectar: Bool { species.traits.producesNectar }
    public var reach: NectarReach { NectarReach(species.traits) }
    /// Whether a honey bee can get at the nectar. False for a foxglove and for
    /// a poppy, for quite different reasons — `reach` says which.
    public var canReachNectar: Bool { reach == .withinReach || reach == .atTheLimit }
    public var nectarRichness: Double { species.nectarRichness }
    public var pollenRichness: Double { species.pollenRichness }

    // MARK: When

    /// Seasons in the order the year runs, rather than a set's arbitrary one.
    public var bloomSeasons: [Season] {
        Season.allCases.filter(species.bloomSeasons.contains)
    }

    /// Months, 1...12, this plant flowers in for the given hemisphere.
    public func bloomMonths(in hemisphere: Hemisphere) -> [Int] {
        bloomSeasons
            .flatMap { BloomCalendar.months(of: $0, in: hemisphere) }
            .sorted()
    }

    public func isInBloom(during season: Season) -> Bool {
        species.isInBloom(during: season)
    }

    public func isInBloom(on date: Date = Date(), in hemisphere: Hemisphere = .northern) -> Bool {
        isInBloom(during: RealSeason.current(on: date, in: hemisphere))
    }

    /// "Spring and summer", for a list row.
    public var bloomSummary: String {
        bloomSeasons.map(\.displayName).spokenList
    }
}

// MARK: - The guide

/// The catalogue as a book, grouped by family and searchable.
public struct FieldGuide: Equatable, Sendable {

    public struct FamilyGroup: Identifiable, Equatable, Sendable {
        public let family: PlantFamily
        public let entries: [FieldGuideEntry]

        public var id: PlantFamily { family }
        public var photographedCount: Int {
            entries.filter(\.hasBeenPhotographed).count
        }
        /// Whether the player has found nothing at all in this family. What
        /// the collection screen calls a gap.
        public var isUnvisited: Bool { photographedCount == 0 }
    }

    /// Every species the game knows, in the order the families come.
    public let entries: [FieldGuideEntry]

    /// Grouped by family, which is the only grouping that earns its keep: the
    /// family is what decides floral architecture, so the plants a bee treats
    /// alike sit together. Families are ordered by scientific name, as on the
    /// collection screen and in a real flora, and species within a family
    /// alphabetically — a guide is for looking something up.
    public let families: [FamilyGroup]

    public init(patches: [PatchSummary] = []) {
        let found = BotanyCollection(patches: patches).speciesCollected

        let all = FlowerCatalogue.all.map { species in
            FieldGuideEntry(
                species: species,
                fieldNote: Self.fieldNote(for: species),
                hasBeenPhotographed: found.contains(species.id)
            )
        }

        var byFamily: [PlantFamily: [FieldGuideEntry]] = [:]
        for entry in all {
            byFamily[entry.family, default: []].append(entry)
        }

        families = byFamily
            .map { family, members in
                FamilyGroup(
                    family: family,
                    entries: members.sorted { $0.commonName < $1.commonName }
                )
            }
            .sorted { $0.family.scientificName < $1.family.scientificName }

        entries = families.flatMap(\.entries)
    }

    // MARK: Looking things up

    public var speciesTotal: Int { entries.count }
    public var photographedCount: Int { entries.filter(\.hasBeenPhotographed).count }

    /// Species not yet photographed, best forage first — the same order the
    /// collection puts its gaps in.
    public var notYetPhotographed: [FieldGuideEntry] {
        entries
            .filter { !$0.hasBeenPhotographed }
            .sorted {
                $0.nectarRichness + $0.pollenRichness > $1.nectarRichness + $1.pollenRichness
            }
    }

    public func entry(id: String) -> FieldGuideEntry? {
        entries.first { $0.id == id }
    }

    /// Everything flowering now, best nectar first.
    ///
    /// The badge on a list row and the "out now" section come from here rather
    /// than from a view's own date arithmetic.
    public func inBloom(
        during date: Date = Date(),
        hemisphere: Hemisphere = .northern
    ) -> [FieldGuideEntry] {
        let season = RealSeason.current(on: date, in: hemisphere)
        return entries
            .filter { $0.isInBloom(during: season) }
            .sorted { $0.nectarRichness > $1.nectarRichness }
    }

    /// Search over the names a person might actually type: the common name,
    /// the scientific name, the genus on its own, and both names of the
    /// family. Whole-word matching is what `ClassifierLabels` needs and the
    /// wrong rule here — somebody typing "clo" is halfway through "clover".
    ///
    /// An empty query returns the whole guide, so a search field can drive the
    /// list without the caller special-casing it.
    public func search(_ query: String) -> [FieldGuideEntry] {
        let needle = ClassifierLabels.normalise(query)
        guard !needle.isEmpty else { return entries }

        let matches = entries.filter { entry in
            let haystacks = [
                entry.commonName,
                entry.scientificName,
                entry.genus ?? "",
                entry.family.scientificName,
                entry.family.commonName
            ]
            return haystacks.contains {
                ClassifierLabels.normalise($0).contains(needle)
            }
        }

        // Nothing matched by name, so try the synonym table before giving up:
        // linden, canola, blackberry and starflower are all things a person
        // might reasonably call a plant in this catalogue.
        if matches.isEmpty, let species = FlowerCatalogue.match(label: query) {
            return entry(id: species.id).map { [$0] } ?? []
        }

        return matches
    }

    // MARK: - What to look for

    /// One sentence per species: the marks that identify it, and the ground it
    /// grows on.
    ///
    /// Keyed by catalogue identifier rather than switched over, because
    /// `FlowerSpecies.id` is a string and a switch over strings would be no
    /// safer than this. `FieldGuideTests` checks every species in the
    /// catalogue has one, which is the guard that matters: adding a plant and
    /// forgetting to describe it fails the suite.
    public static let fieldNotes: [String: String] = [
        "crocus":
            "A goblet of six petals straight out of cold ground, with three orange stigmas inside. Lawns, park verges and churchyards, from February.",
        "willow":
            "Grey furry catkins on bare twigs before any leaf, turning gold as the pollen ripens. Damp ground, riverbanks and scrub.",
        "dandelion":
            "A single yellow disc of ribbon florets on a hollow leafless stalk that bleeds white sap, over a flat rosette of toothed leaves.",
        "apple":
            "Five white petals flushed pink on the outside of the bud, in clusters along the twigs of an orchard or garden tree.",
        "hawthorn":
            "Flat dense sprays of small white flowers with pink-brown anthers, heavily scented, on a thorny hedgerow tree.",
        "oilseed_rape":
            "Whole fields of four-petalled yellow crosses in a spike, over blue-green leaves that clasp the stem.",
        "bluebell":
            "A one-sided nodding spike of narrow violet bells with rolled-back tips, carpeting old woodland.",
        "cherry":
            "White blossom in long-stalked clusters on a smooth grey trunk banded with horizontal lines, out before the leaves are fully open.",
        "white_clover":
            "A tight round head of small white pea flowers browning from the base up, in every mown lawn, over leaves in threes with a pale chevron.",
        "borage":
            "Five-pointed blue stars with a black cone of anthers, nodding from bristly grey stems. Herb gardens and field margins.",
        "lavender":
            "Whorls of small violet tubes in a spike above grey needle leaves. The scent names it before you are close enough to look.",
        "bramble":
            "White to pink five-petalled flowers with a boss of stamens, on arching prickly stems in hedges and waste ground.",
        "lime":
            "Hanging clusters of small yellow-green flowers under a strap-shaped bract, high in a big street tree. Look up, or listen.",
        "phacelia":
            "Coiled heads of lavender-blue flowers uncurling like a fern, with long protruding stamens. Sown deliberately in field margins.",
        "sunflower":
            "One large disc ringed with yellow rays and studded with hundreds of tiny florets, on a rough hairy stem.",
        "thistle":
            "A brush of lilac florets over a narrow bud, on an unwinged stem in pasture and on roadsides. It spreads in patches from creeping roots.",
        "foxglove":
            "A tall one-sided spike of speckled purple thimbles, each deep enough to take a bumblebee whole. Woodland edge and acid banks.",
        "poppy":
            "Four crumpled scarlet petals with a black basal blotch around a black boss of anthers. Disturbed ground and field margins.",
        "echinacea":
            "Drooping pink-purple rays around a stiff orange cone. A border plant rather than a wild one.",
        "rosemary":
            "Small two-lipped pale blue flowers in the leaf axils of a resinous evergreen shrub, opening in any mild spell.",
        "heather":
            "A haze of tiny pink-purple bells crowded up wiry stems, colouring whole moors from August. Acid, peaty ground.",
        "ivy":
            "Globes of green-yellow flowers on the mature climbing growth, where the leaves lose their lobes. Old walls and trees, loud with insects in October.",
        "balsam":
            "Pink hooded flowers on two metres of hollow red-jointed stem, in stands along riverbanks. The seed pods spring open at a touch.",
        "goldenrod":
            "Narrow plumes of small golden daisies in late summer, on dry banks and railway ground.",
        "aster":
            "Sprays of small lilac daisies with a yellow eye, flowering into October in gardens and on waste ground.",
        "sedum":
            "A flat pink plate of tiny star flowers over thick grey succulent leaves. A garden plant, covered in bees all autumn.",
        "winter_heather":
            "Low mats of narrow rose-pink bells over dark needle foliage, out from midwinter in rockeries and gardens.",
        "mahonia":
            "Upright clusters of scented lemon-yellow flowers over spiny holly-like evergreen leaves, in the depth of winter.",
        "vipers_bugloss":
            "A bristly spike of funnel-shaped blue flowers with long red stamens curving out of them. Chalk, shingle and dunes.",
        "meadowsweet":
            "Frothy creamy-white heads smelling of almonds, on damp meadows and ditch sides. All scent and pollen, and no nectar at all."
    ]

    /// The note for a species, falling back to what the family means to a
    /// colony. A plant placed only to a family has no field marks of its own
    /// to give, and the family note is a true thing to say about it.
    public static func fieldNote(for species: FlowerSpecies) -> String {
        fieldNotes[species.id] ?? species.family.forageNote
    }
}
