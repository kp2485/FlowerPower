import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// The collection, the prompt, the digest, and the swarm that travels.
@Suite("The long game")
struct LongGameTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func patch(
        _ species: FlowerSpecies?,
        taxon: Taxon? = nil,
        inBloom: Bool = true,
        id: UInt64 = 1
    ) -> PatchSummary {
        let resolved = species?.taxon ?? taxon
        return PatchSummary(
            id: EntityID(rawValue: id),
            photoLocalIdentifier: "p\(id)",
            speciesName: species?.commonName ?? resolved?.scientificName ?? "Unknown",
            isIdentified: resolved != nil,
            rarity: species?.rarity ?? .common,
            coordinate: nil, distanceMetres: 500,
            isInBloom: inBloom, isWithinRange: true,
            remainingFraction: 1, foragersWorkingIt: 0, discoveredAt: epoch,
            vigour: 1, origin: .photographed, sharedBy: nil,
            taxon: resolved, nectarIsOutOfReach: species?.nectarIsOutOfReach ?? false
        )
    }

    // MARK: - Collection

    @Test("An empty garden has every family missing")
    func emptyCollection() {
        let collection = BotanyCollection(patches: [])
        #expect(collection.familiesSeen == 0)
        #expect(collection.missingFamilies.count == PlantFamily.allCases.count)
        #expect(collection.calendarCoverage == 0)
    }

    @Test("Species and families are counted from the garden")
    func counting() {
        let collection = BotanyCollection(patches: [
            patch(FlowerCatalogue.whiteClover, id: 1),
            patch(FlowerCatalogue.whiteClover, id: 2),
            patch(FlowerCatalogue.ivy, id: 3),
            patch(nil, taxon: Taxon(family: .boraginaceae), id: 4)
        ])

        #expect(collection.familiesSeen == 3)
        #expect(collection.speciesCollected == ["white_clover", "ivy"])
        #expect(collection.families.first { $0.family == .fabaceae }?.patchCount == 2)
        #expect(collection.families.first { $0.family == .boraginaceae }?.bestRank == .family)
        #expect(!collection.missingFamilies.contains(.fabaceae))
    }

    @Test("The calendar is covered by what the garden's plants flower in")
    func calendar() {
        // Clover covers spring, summer and autumn; ivy adds nothing new; a
        // winter heather fills the gap.
        let partial = BotanyCollection(patches: [patch(FlowerCatalogue.whiteClover)])
        #expect(partial.seasonsMissing == [.winter])

        let full = BotanyCollection(patches: [
            patch(FlowerCatalogue.whiteClover, id: 1),
            patch(FlowerCatalogue.winterHeather, id: 2)
        ])
        #expect(full.calendarCoverage == 1)
    }

    // MARK: - The prompt

    @Test("Real seasons follow the meteorological calendar", arguments: [
        (3, Hemisphere.northern, Season.spring), (7, .northern, .summer),
        (10, .northern, .autumn), (1, .northern, .winter),
        (3, .southern, .autumn), (12, .southern, .summer)
    ])
    func realSeasons(month: Int, hemisphere: Hemisphere, expected: Season) {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 15
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(RealSeason.current(on: date, in: hemisphere) == expected)
    }

    @Test("The prompt points at what is out and not yet found")
    func prompt() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        let october = Calendar(identifier: .gregorian).date(from: components)!

        let prompt = BloomPrompt(date: october, hemisphere: .northern, patches: [
            patch(FlowerCatalogue.ivy)
        ])

        #expect(prompt.season == .autumn)
        #expect(prompt.inBloom.contains { $0.id == "ivy" })
        #expect(!prompt.notYetPhotographed.contains { $0.id == "ivy" }, "already have it")
        #expect(prompt.notYetPhotographed.contains { $0.id == "heather" })
        #expect(!prompt.missingFamilies.contains(.araliaceae), "ivy's family is held")
        #expect(!prompt.headline.isEmpty)
    }

    // MARK: - The digest

    private func snapshot(days: Int, seed: UInt64 = 8) -> (ColonySnapshot, CatchUpReport) {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: seed
        )
        for index in 0..<6 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "p\(index)",
                species: FlowerCatalogue.all[index], confidence: 0.9,
                coordinate: nil, takenAt: epoch, distanceMetres: 500
            )
        }
        for _ in 0..<days { _ = simulation.stepDay() }
        let target = simulation.date(afterSimulatedDays: 12)
        let report = simulation.advance(to: target)
        return (simulation.snapshot(), report)
    }

    @Test("A quiet day in a steady colony is not news")
    func quietDigest() {
        let quiet = CatchUpReport()
        let (snapshot, _) = snapshot(days: 30)
        #expect(DailyDigest.make(from: quiet, snapshot: snapshot) == nil)
    }

    @Test("A day with events makes a digest")
    func digest() {
        let (snapshot, report) = snapshot(days: 30)
        var loud = report
        loud.record(.swarmed(beesLost: 80))
        loud.record(.attacked(.wasp))

        let digest = DailyDigest.make(from: loud, snapshot: snapshot)
        #expect(digest != nil)
        #expect(digest?.body.contains("A swarm left.") == true)
        #expect(digest?.body.contains("wasp") == true)
    }

    @Test("Spoken lists read as English")
    func spokenLists() {
        #expect([String]().spokenList == "")
        #expect(["a"].spokenList == "a")
        #expect(["a", "b"].spokenList == "a and b")
        #expect(["a", "b", "c"].spokenList == "a, b and c")
    }

    @Test("The digest schedule is clamped to a real time of day")
    func schedule() {
        let schedule = DailyDigest.Schedule(hour: 99, minute: -5)
        #expect(schedule.hour == 23)
        #expect(schedule.minute == 0)
    }

    // MARK: - Swarms between players

    private func departed() -> DepartedSwarm {
        DepartedSwarm(
            day: 100,
            queen: Bee(id: EntityID(rawValue: 1), kind: .queen, stage: .adult, daysInStage: 200),
            workers: (0..<50).map { Bee(id: EntityID(rawValue: UInt64(10 + $0)), kind: .worker, stage: .adult, daysInStage: 25) },
            genetics: QueenGenetics(patrilines: 14),
            honeyCarried: 6,
            queenNumber: 2
        )
    }

    @Test("A swarm round-trips through its file")
    func swarmRoundTrip() throws {
        var lineage = Lineage()
        lineage.found(onDay: 0, patrilines: 12)
        lineage.end(onDay: 50, .superseded)
        lineage.crown(onDay: 55, quality: 0.9)
        lineage.name(2, "Boudicca")

        let share = SwarmShare(departed(), lineage: lineage, sharedBy: "Kyle", note: "Catch!")
        let restored = try SwarmShare.decoded(from: share.encoded())

        #expect(restored.workerCount == 50)
        #expect(restored.queenTitle == "Boudicca")
        #expect(restored.genetics.patrilines == 14)
        #expect(restored.sharedBy == "Kyle")
    }

    @Test("A swarm file is clamped to something a colony could be")
    func swarmClamping() {
        let absurd = SwarmShare(
            queen: nil, workerCount: 50_000,
            genetics: QueenGenetics(patrilines: 900, hygienicBehaviour: 7, defensiveness: -1,
                                    fecundity: .nan, swarminess: 2, thriftiness: 0.5),
            honeyCarried: .infinity, sharedBy: String(repeating: "x", count: 300)
        ).validated()

        #expect(absurd.workerCount == SwarmShare.maximumWorkers)
        #expect(absurd.genetics.patrilines == 30)
        #expect(absurd.genetics.hygienicBehaviour == 1)
        #expect(absurd.genetics.defensiveness == 0)
        #expect(absurd.genetics.fecundity == 1)
        #expect(absurd.honeyCarried == 0)
        #expect(absurd.sharedBy?.count == 80)
    }

    @Test("Rubbish is not a swarm")
    func notASwarm() {
        #expect(throws: SwarmShare.Failure.notASwarmFile) {
            try SwarmShare.decoded(from: Data("hello".utf8))
        }
    }

    @Test("A swarm with no bees is refused")
    func emptySwarm() throws {
        var empty = SwarmShare(departed(), lineage: Lineage(), sharedBy: nil)
        empty.workerCount = 0
        #expect(throws: SwarmShare.Failure.noBees) {
            try SwarmShare.decoded(from: empty.encoded())
        }
    }

    @Test("A received swarm founds a colony with fresh identifiers")
    func foundFromShare() {
        let share = SwarmShare(departed(), lineage: Lineage(), sharedBy: "Kyle")
        let colony = Simulation.newGame(
            fromSwarm: share.departedSwarm(), at: HiveLocation(type: .cave),
            startingAt: epoch, seed: 3
        )

        #expect(colony.hive.adultCount == 51)
        #expect(colony.hive.queenIsMated)
        let ids = colony.hive.bees.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(.unassigned))
    }

    // MARK: - Asking for a flower

    @Test("A request carries families and no photograph")
    func request() throws {
        let request = FlowerShare.request(
            wanted: [.araliaceae, .ericaceae, .araliaceae], season: .autumn,
            sharedBy: "Kyle", note: "Short of ivy"
        ).validated()

        #expect(request.isRequest)
        #expect(request.wanted == [.araliaceae, .ericaceae], "deduplicated")
        #expect(request.imageData.isEmpty)
        #expect(request.requestSummary == "Kyle's bees are short of ivy family and heather family.")

        // A request survives the file, where a gift with no image would not.
        let restored = try FlowerShare.decoded(from: request.encoded())
        #expect(restored.isRequest)
    }

    @Test("A gift never carries a request's fields")
    func giftHasNoWanted() {
        var gift = FlowerShare(
            speciesID: "ivy", confidence: 0.9, takenAt: epoch, sharedBy: nil,
            imageData: Data([1, 2, 3])
        )
        gift.wanted = [.araliaceae]
        #expect(gift.validated().wanted == nil)
    }
}
