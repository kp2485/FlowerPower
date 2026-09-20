import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// The catch-up report, condensed.
///
/// The failure this guards against is a quiet one and it has already happened
/// once on screen: a chatty event fires forty times, fills the highlight cap,
/// and the player opens the app to forty identical sentences with the lost
/// queen nowhere on the page. So the tests are mostly about crowding — that a
/// group is capped, that the cap is per group rather than overall, and that
/// severity decides the order however many of the quiet things there are.
@Suite("Report digest")
struct ReportDigestTests {

    // MARK: - Grouping

    @Test("Every kind of event lands under a heading, and severe news leads")
    func groupsAreOrderedBySeverity() {
        let digest = ReportDigest(highlights: [
            .weatherChanged(.cloudy),
            .patchOutOfBloom(EntityID(rawValue: 1)),
            .queenLost,
            .attacked(.wasp)
        ])

        #expect(digest.groups.map(\.category) == [.colony, .defence, .forage])
        #expect(digest.totalCount == 4)
        #expect(!digest.isEmpty)
    }

    @Test("A group keeps its events in the order they happened")
    func arrivalOrderIsKept() {
        let digest = ReportDigest(highlights: [
            .queenCellStarted(.swarm),
            .swarmed(beesLost: 240),
            .queenEmerged(quality: 0.95)
        ])

        let colony = digest.group(.colony)
        #expect(colony?.count == 3)
        #expect(colony?.lines.first?.text == SimEvent.queenCellStarted(.swarm).narration)
        #expect(colony?.lines.last?.text == SimEvent.queenEmerged(quality: 0.95).narration)
    }

    @Test("Two equally grave groups always come out the same way round")
    func tiesBreakOnDeclarationOrder() {
        let events: [SimEvent] = [.infectionDetected(.varroa), .attacked(.wasp)]
        let one = ReportDigest(highlights: events)
        let other = ReportDigest(highlights: events.reversed())

        #expect(one.groups.map(\.category) == [.defence, .health])
        #expect(other.groups.map(\.category) == [.defence, .health])
    }

    // MARK: - Counting

    @Test("A group's summary counts by kind: 3 raids, 2 driven off")
    func summaryCountsByKind() {
        let digest = ReportDigest(highlights: [
            .raidSucceeded(.hornet, storesLost: 12),
            .raidSucceeded(.wasp, storesLost: 3),
            .raidSucceeded(.badger, storesLost: 40),
            .attackRepelled(.wasp),
            .attackRepelled(.mouse)
        ])

        #expect(digest.group(.defence)?.summary == "3 raids, 2 driven off")
    }

    @Test("One of a kind is counted in the singular")
    func singularIsUsedForOne() {
        let digest = ReportDigest(highlights: [.raidSucceeded(.hornet, storesLost: 12)])
        #expect(digest.group(.defence)?.summary == "1 raid")
    }

    @Test("The same sentence twice is one line with a count, not two lines")
    func identicalSentencesFold() {
        let digest = ReportDigest(highlights: [
            .patchOutOfBloom(EntityID(rawValue: 1)),
            .patchOutOfBloom(EntityID(rawValue: 2)),
            .patchOutOfBloom(EntityID(rawValue: 3))
        ])

        let forage = digest.group(.forage)
        #expect(forage?.count == 3)
        #expect(forage?.lines.count == 1)
        #expect(forage?.lines.first?.count == 3)
        #expect(forage?.lines.first?.display.hasSuffix("×3") == true)
        // One line, so nothing is hidden behind an "and more".
        #expect(forage?.overflowLine == nil)
    }

    // MARK: - Crowding

    @Test("No kind of event can crowd another out: the cap is per group")
    func theCapIsPerGroup() {
        // Forty turns in the weather, the way a fortnight away produces them,
        // against one lost queen.
        var highlights: [SimEvent] = (1...40).map {
            .weatherChanged($0.isMultiple(of: 2) ? .cloudy : .rain)
        }
        highlights.append(.queenLost)

        let digest = ReportDigest(highlights: highlights, linesPerGroup: 2)

        // The queen is still on the page, and first.
        #expect(digest.groups.first?.category == .colony)
        #expect(digest.group(.colony)?.visibleLines.count == 1)

        // The weather is capped at two lines and says how much it is holding
        // back, rather than filling the screen.
        let forage = digest.group(.forage)
        #expect(forage?.count == 40)
        #expect(forage?.visibleLines.count == 2)
        #expect(forage?.hiddenCount == 0, "two distinct sentences fit in two lines")
    }

    @Test("A group past the cap says how many events it is holding back")
    func overflowCountsEventsRatherThanLines() {
        // Six distinct sentences under one heading, capped at two lines. The
        // four that do not fit stand for five events between them, and it is
        // the events the overflow line has to count — "and 4 more" would be
        // an undercount of what is being held back.
        let digest = ReportDigest(
            highlights: [
                .honeyTaken(10),
                .honeyTaken(20),
                .fed(5),
                .combAdded(cells: 100),
                .entranceSealed(true),
                .postureAdopted(.holdEntrance),
                .postureAdopted(.holdEntrance)
            ],
            linesPerGroup: 2
        )

        let keeping = digest.group(.keeping)
        #expect(keeping?.lines.count == 6)
        #expect(keeping?.visibleLines.count == 2)
        #expect(keeping?.hiddenCount == 5)
        #expect(keeping?.overflowLine == "and 5 more")
    }

    @Test("A cap of zero still shows a line")
    func theCapIsNeverNothing() {
        let digest = ReportDigest(highlights: [.queenLost, .swarmed(beesLost: 1)], linesPerGroup: 0)
        #expect(digest.group(.colony)?.visibleLines.count == 1)
    }

    // MARK: - Emptiness

    @Test("Nothing in, nothing out")
    func emptyReportGivesEmptyDigest() {
        let digest = ReportDigest(highlights: [])
        #expect(digest.isEmpty)
        #expect(digest.groups.isEmpty)
        #expect(digest.totalCount == 0)
    }

    @Test("A real report's highlights all find a home")
    func everyHighlightIsAccountedFor() {
        var report = CatchUpReport()
        for event in Self.oneOfEverything {
            report.record(event)
        }

        let digest = ReportDigest(report: report)
        #expect(digest.totalCount == report.highlights.count)
        #expect(digest.groups.reduce(0) { $0 + $1.count } == report.highlights.count)
    }

    /// Every case a highlight can be, so a case added to the engine and left
    /// out of `SimEvent.category` shows up here rather than on a player's
    /// screen under the wrong heading.
    private static let oneOfEverything: [SimEvent] = [
        .queenCellStarted(.emergency), .queenEmerged(quality: 0.8),
        .queenMated(patrilines: 12), .matingFlightFailed, .queenLost,
        .queenFailing, .swarmed(beesLost: 200), .absconded(beesLost: 900),
        .supersededQueen, .layingWorkersAppeared, .colonyCollapsed,
        .combLost(count: 40), .patchOutOfBloom(EntityID(rawValue: 7)),
        .nectarFlowBegan, .dearth, .weatherChanged(.clear),
        .infectionDetected(.varroa), .infectionCleared(.varroa),
        .infectionCritical(.varroa), .attacked(.wasp),
        .attackRepelled(.wasp), .raidSucceeded(.hornet, storesLost: 5),
        .winterStoresLow(have: 10, need: 40), .threatBegan(.hornet, resolvesOnDay: 9),
        .threatEnded(.hornet), .swarmPreparing(departsOnDay: 4), .swarmAbandoned,
        .postureAdopted(.instinct), .entranceSealed(false), .honeyTaken(8),
        .fed(3), .combAdded(cells: 200), .colonyDivided(beesLeft: 300),
        .milestone(.firstFlower)
    ]

    @Test("Every event the engine can raise has a heading and a countable name")
    func everyCaseIsNamed() {
        for event in Self.oneOfEverything {
            let phrase = event.digestPhrase
            #expect(!phrase.singular.isEmpty)
            #expect(!phrase.plural.isEmpty)
            #expect(phrase.counted(1).hasPrefix("1 "))
            #expect(phrase.counted(3) == "3 \(phrase.plural)")
            // The category is an exhaustive switch; asking for it is the test.
            #expect(HighlightCategory.allCases.contains(event.category))
        }
    }

    @Test("Every heading has words and a symbol")
    func everyCategoryIsPresentable() {
        for category in HighlightCategory.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.symbolName.isEmpty)
        }
    }
}
