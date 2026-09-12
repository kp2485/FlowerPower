import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// The guide to the whole catalogue, as against the collection of what has
/// been found.
///
/// What can go wrong here is coverage: a species added to the catalogue and
/// left out of the guide, a family group that quietly drops a plant, a search
/// that only knows common names. None of it would show on screen as anything
/// but an absence.
@Suite("Field guide")
struct FieldGuideTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Same shape as `LongGameTests.patch`: a snapshot patch is what the guide
    /// reads to decide whether the player has found a plant.
    private func patch(_ species: FlowerSpecies, id: UInt64 = 1) -> PatchSummary {
        PatchSummary(
            id: EntityID(rawValue: id),
            photoLocalIdentifier: "p\(id)",
            speciesName: species.commonName,
            isIdentified: true,
            rarity: species.rarity,
            coordinate: nil, distanceMetres: 500,
            isInBloom: true, isWithinRange: true,
            remainingFraction: 1, foragersWorkingIt: 0, discoveredAt: epoch,
            vigour: 1, origin: .photographed, sharedBy: nil,
            taxon: species.taxon, nectarIsOutOfReach: species.nectarIsOutOfReach
        )
    }

    // MARK: - Coverage

    @Test("Every species in the catalogue has exactly one entry")
    func everySpeciesHasAnEntry() {
        let guide = FieldGuide()

        #expect(guide.entries.count == FlowerCatalogue.all.count)
        #expect(Set(guide.entries.map(\.id)) == Set(FlowerCatalogue.all.map(\.id)))

        for species in FlowerCatalogue.all {
            let matches = guide.entries.filter { $0.id == species.id }
            #expect(matches.count == 1, "\(species.commonName) has \(matches.count) entries")
            #expect(matches.first?.species == species)
        }
    }

    @Test("Grouping by family covers every entry exactly once")
    func familiesCoverEverything() {
        let guide = FieldGuide()
        let regrouped = guide.families.flatMap(\.entries)

        #expect(regrouped.count == guide.entries.count)
        #expect(Set(regrouped.map(\.id)) == Set(guide.entries.map(\.id)))

        // Families in botanical order, entries alphabetical inside them, and
        // every entry filed under its own family.
        let names = guide.families.map(\.family.scientificName)
        #expect(names == names.sorted())
        for group in guide.families {
            #expect(!group.entries.isEmpty)
            #expect(group.entries.allSatisfy { $0.family == group.family })
            let common = group.entries.map(\.commonName)
            #expect(common == common.sorted())
        }
    }

    /// A guide that lists a plant's nectar sugar and says nothing about its
    /// petals is not a field guide. Adding a species and forgetting to describe
    /// it fails here rather than shipping a page with the family's note on it.
    @Test("Every species is described well enough to find in a hedgerow")
    func everySpeciesHasAFieldNote() {
        for species in FlowerCatalogue.all {
            let note = FieldGuide.fieldNotes[species.id]
            #expect(note != nil, "\(species.commonName) has no field note")
            #expect((note?.count ?? 0) > 40, "\(species.commonName) is barely described")
            #expect(note?.hasSuffix(".") == true, "\(species.commonName)'s note is not a sentence")
        }
        #expect(FieldGuide.fieldNotes.count == FlowerCatalogue.all.count)
    }

    // MARK: - What the player has found

    @Test("A photographed species is marked, and only that species")
    func photographedSpeciesAreMarked() {
        let guide = FieldGuide(patches: [
            patch(FlowerCatalogue.whiteClover, id: 1),
            patch(FlowerCatalogue.ivy, id: 2)
        ])

        #expect(guide.photographedCount == 2)
        #expect(guide.entry(id: "white_clover")?.hasBeenPhotographed == true)
        #expect(guide.entry(id: "ivy")?.hasBeenPhotographed == true)
        #expect(guide.entry(id: "foxglove")?.hasBeenPhotographed == false)

        // The fabaceae group knows one of its two plants has been found; the
        // families with nothing in them are the collection's gaps.
        let peas = guide.families.first { $0.family == .fabaceae }
        #expect(peas?.photographedCount == 1)
        #expect(peas?.isUnvisited == false)
        #expect(guide.families.first { $0.family == .plantaginaceae }?.isUnvisited == true)

        #expect(guide.notYetPhotographed.count == FlowerCatalogue.all.count - 2)
        #expect(!guide.notYetPhotographed.contains { $0.id == "ivy" })
    }

    @Test("An empty garden has found nothing")
    func emptyGarden() {
        let guide = FieldGuide()
        #expect(guide.photographedCount == 0)
        #expect(guide.notYetPhotographed.count == guide.speciesTotal)
        #expect(guide.families.allSatisfy { $0.isUnvisited })
    }

    // MARK: - Search

    @Test("Search finds a plant by its scientific name and by its family")
    func searchByName() {
        let guide = FieldGuide()

        #expect(guide.search("Trifolium repens").map(\.id) == ["white_clover"])
        #expect(guide.search("trifolium").map(\.id) == ["white_clover"])
        #expect(guide.search("Digitalis").map(\.id) == ["foxglove"])

        // Both names of a family, and every member of it.
        let borages = Set(guide.search("Boraginaceae").map(\.id))
        #expect(borages == ["borage", "phacelia", "vipers_bugloss"])
        #expect(Set(guide.search("borage family").map(\.id)) == borages)

        // Common names, including a partial word, which is what a search field
        // actually receives.
        #expect(guide.search("clo").map(\.id) == ["white_clover"])
        #expect(guide.search("heather").count == 2)

        // An empty query is the whole book, so a search field can drive the
        // list without the view special-casing it.
        #expect(guide.search("").count == guide.speciesTotal)

        // And the synonym table is the last resort: nobody calls it Tilia.
        #expect(guide.search("linden").map(\.id) == ["lime"])
        #expect(guide.search("blackberry").map(\.id) == ["bramble"])
        #expect(guide.search("wisteria").isEmpty)
    }

    // MARK: - When it flowers

    @Test("In bloom now follows the real calendar and the hemisphere")
    func inBloomNow() {
        let guide = FieldGuide()
        let calendar = Calendar(identifier: .gregorian)
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let northernSummer = guide.inBloom(during: july, hemisphere: .northern)
        #expect(northernSummer.contains { $0.id == "foxglove" })
        #expect(!northernSummer.contains { $0.id == "crocus" })
        // Best nectar first, the same order the catalogue uses.
        #expect(northernSummer.map(\.nectarRichness) == northernSummer.map(\.nectarRichness).sorted(by: >))

        // The same date south of the equator is midwinter, and two plants in
        // the catalogue flower then — both keystones.
        let southernWinter = guide.inBloom(during: july, hemisphere: .southern)
        #expect(southernWinter.allSatisfy { $0.isInBloom(during: .winter) })
        #expect(southernWinter.allSatisfy { $0.isKeystone })
        #expect(southernWinter.contains { $0.id == "mahonia" })
    }

    @Test("A plant's bloom months are the months of the seasons it flowers in")
    func bloomMonths() {
        let guide = FieldGuide()
        let crocus = guide.entry(id: "crocus")!

        #expect(crocus.bloomSeasons == [.spring])
        #expect(crocus.bloomMonths(in: .northern) == [3, 4, 5])
        #expect(crocus.bloomMonths(in: .southern) == [9, 10, 11])

        // Seasons come back in the order the year runs, not a set's order.
        let clover = guide.entry(id: "white_clover")!
        #expect(clover.bloomSeasons == [.spring, .summer, .autumn])
        #expect(clover.bloomMonths(in: .northern) == [3, 4, 5, 6, 7, 8, 9, 10, 11])
        #expect(clover.bloomSummary == "Spring, Summer and Autumn")

        // Winter straddles the year end, so its months are not contiguous.
        #expect(BloomCalendar.months(of: .winter, in: .northern) == [1, 2, 12])
        #expect(BloomCalendar.monthName(3) == "March")
        #expect(BloomCalendar.monthInitial(7) == "J")
    }

    /// The strip on a flower's page and the prompt that says what is out now
    /// must never disagree about when spring is.
    @Test("The calendar agrees with the prompt about which season a month is in")
    func calendarMatchesRealSeason() {
        let calendar = Calendar(identifier: .gregorian)
        for month in 1...12 {
            for hemisphere in [Hemisphere.northern, .southern] {
                let date = calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
                let expected = RealSeason.current(on: date, in: hemisphere)
                #expect(BloomCalendar.season(ofMonth: month, in: hemisphere) == expected)
                #expect(BloomCalendar.months(of: expected, in: hemisphere).contains(month))
            }
        }
        // Every month belongs to exactly one season.
        for hemisphere in [Hemisphere.northern, .southern] {
            let all = Season.allCases.flatMap { BloomCalendar.months(of: $0, in: hemisphere) }
            #expect(all.sorted() == Array(1...12))
        }
    }

    // MARK: - Whether a honey bee can work it

    /// The verdict a list row shows has to come out of the same traits the
    /// engine forages on, or the guide would be telling the player something
    /// their bees disagree with.
    @Test("The reach verdict matches what the bees can actually do")
    func reachVerdicts() {
        let guide = FieldGuide()

        // Well within reach: a 2 mm clover tube against nearly 8 mm of bee.
        let clover = guide.entry(id: "white_clover")!
        #expect(clover.reach == .withinReach)
        #expect(clover.canReachNectar)

        // A bumblebee flower, over 20 mm deep.
        let foxglove = guide.entry(id: "foxglove")!
        #expect(foxglove.reach == .outOfReach)
        #expect(!foxglove.canReachNectar)
        #expect(foxglove.producesNectar)

        // A bluebell at 10 mm is just past her, which is not the same thing.
        let bluebell = guide.entry(id: "bluebell")!
        #expect(bluebell.reach == .atTheLimit)
        #expect(bluebell.canReachNectar)

        // And a poppy is out of reach of nobody: there is simply no nectar.
        let poppy = guide.entry(id: "poppy")!
        #expect(poppy.reach == .nectarless)
        #expect(!poppy.producesNectar)
        #expect(!poppy.canReachNectar)
        #expect(poppy.pollenRichness > 1)

        // Every verdict says something, in both registers.
        for verdict in NectarReach.allCases {
            #expect(!verdict.displayName.isEmpty)
            #expect(verdict.detail.hasSuffix("."))
            #expect(verdict.detail.count > 40)
            #expect(verdict.isWorkable == (verdict == .withinReach || verdict == .atTheLimit))
        }
    }

    @Test("An entry reads its facts off the catalogue rather than keeping its own")
    func entriesDoNotDuplicateTheCatalogue() {
        let guide = FieldGuide()
        for entry in guide.entries {
            let species = FlowerCatalogue.species(withID: entry.id)
            #expect(entry.traits == species?.traits)
            #expect(entry.rarity == species?.rarity)
            #expect(entry.scientificName == species?.scientificName)
            #expect(entry.isKeystone == species?.isKeystone)
            #expect(entry.family == species?.family)
            #expect(entry.genus != nil, "\(entry.commonName) is not placed to a genus")
            #expect(!entry.bloomSeasons.isEmpty)
        }
    }
}
