import Testing
import Foundation
@testable import FlowerPowerCore

/// The comb, as something a finger lands on.
///
/// The arrangement used to live inside a `Canvas` closure in a file no
/// compiler on this machine can see, which meant the one part of the nest the
/// player is now going to touch was the one part nothing could check. These
/// tests are the reason it moved into the package: that the comb accounts for
/// exactly the cells the colony has drawn, that its tallies are the hive's own
/// numbers rather than a second estimate of them, that the same snapshot gives
/// the same comb twice — and that every hexagon on it can say what it is.
@Suite("Comb layout")
struct CombLayoutTests {

    // MARK: - Fixtures

    /// An established colony a month into its first spring: brood at every
    /// stage, stores of four kinds, and comb still to fill.
    private func establishedSnapshot() -> ColonySnapshot {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(30)
        return simulation.snapshot()
    }

    // MARK: - The comb covers the nest

    @Test("The layout draws exactly the cells the colony has built")
    func coversTheBuiltCells() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        #expect(snapshot.nest.builtCells > 0)
        #expect(layout.builtCells == snapshot.nest.builtCells)
        #expect(layout.cells.count == min(snapshot.nest.builtCells, CombLayout.maximumCellsDrawn))
        #expect(!layout.isTruncated)

        // The indices are the drawing order, with no gaps: the interface walks
        // them straight into `CombGeometry`.
        for (position, cell) in layout.cells.enumerated() {
            #expect(cell.index == position)
        }
    }

    @Test("A nest larger than the canvas can show is truncated, and says so")
    func truncatesAVeryLargeNest() {
        var simulation = Fixture.thrivingSimulation(drawnComb: 1_400)
        simulation.runDays(5)
        let layout = CombLayout(snapshot: simulation.snapshot())

        #expect(layout.builtCells > CombLayout.maximumCellsDrawn)
        #expect(layout.cells.count == CombLayout.maximumCellsDrawn)
        #expect(layout.isTruncated)
    }

    // MARK: - The tallies are the hive's own numbers

    @Test("Brood cells match the colony's brood, stage by stage")
    func broodCountsMatchThePopulation() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)
        let population = snapshot.population

        #expect(population.brood > 0)
        #expect(layout.count(of: .eggs) == population.eggs)
        #expect(layout.count(of: .larvae) == population.larvae)
        #expect(layout.count(of: .sealedBrood) == population.pupae)

        // And the brood the nest reports is the brood the population reports:
        // two counts of the same bees, taken by different routes.
        #expect(snapshot.nest.brood.count == population.brood)
    }

    @Test("Stores fill the number of cells the engine says they occupy")
    func storesFillTheirOwnCells() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        var expected = 0
        for (kind, family) in [
            (ResourceKind.beeBread, CombCellFamily.beeBread),
            (.pollen, .pollen),
            (.nectar, .nectar),
            (.honey, .honey)
        ] {
            let amount = snapshot.stores.resources[kind] ?? 0
            let cells = amount > 0 ? Int((amount / kind.unitsPerCell).rounded(.up)) : 0
            #expect(layout.count(of: family) == cells)
            expected += cells
        }

        #expect(expected > 0)
    }

    @Test("Every built cell is accounted for exactly once")
    func everyCellIsAccountedFor() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        let tallied = CombCellFamily.allCases.reduce(0) { $0 + layout.count(of: $1) }
        #expect(tallied == layout.cells.count)

        // Nothing left over, and nothing counted twice.
        for family in CombCellFamily.allCases {
            #expect(layout.indices(of: family).count == layout.count(of: family))
        }
    }

    // MARK: - Concentric

    @Test("Brood is in the middle, pollen around it, honey outside")
    func theArrangementIsConcentric() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        func lastIndex(of family: CombCellFamily) -> Int? {
            layout.indices(of: family).last
        }
        func firstIndex(of family: CombCellFamily) -> Int? {
            layout.indices(of: family).first
        }

        // Every brood cell comes before every cell of stores.
        if let lastBrood = lastIndex(of: .sealedBrood),
           let firstStore = firstIndex(of: .honey) {
            #expect(lastBrood < firstStore)
        }
        // Eggs inside larvae inside sealed brood.
        if let lastEgg = lastIndex(of: .eggs), let firstLarva = firstIndex(of: .larvae) {
            #expect(lastEgg < firstLarva)
        }
        if let lastLarva = lastIndex(of: .larvae), let firstPupa = firstIndex(of: .sealedBrood) {
            #expect(lastLarva < firstPupa)
        }
        // Protein before the honey it is kept inside of.
        if let lastPollen = lastIndex(of: .pollen), let firstHoney = firstIndex(of: .honey) {
            #expect(lastPollen < firstHoney)
        }
        // And empty comb at the edge, after everything.
        if let firstEmpty = firstIndex(of: .empty) {
            for family in CombCellFamily.allCases where family != .empty {
                if let last = lastIndex(of: family) { #expect(last < firstEmpty) }
            }
        }
    }

    // MARK: - Determinism

    @Test("The same snapshot gives the same comb")
    func theLayoutIsDeterministic() {
        let snapshot = establishedSnapshot()

        let first = CombLayout(snapshot: snapshot)
        let second = CombLayout(snapshot: snapshot)

        #expect(first.cells == second.cells)
        #expect(first.regions == second.regions)
        #expect(first.counts == second.counts)
    }

    @Test("Two runs of the same seed lay out the same comb")
    func twoRunsOfTheSameSeedAgree() {
        var one = Fixture.thrivingSimulation(seed: 99)
        var two = Fixture.thrivingSimulation(seed: 99)
        one.runDays(21)
        two.runDays(21)

        #expect(CombLayout(snapshot: one.snapshot()).cells
            == CombLayout(snapshot: two.snapshot()).cells)
    }

    // MARK: - Every cell can say what it is

    @Test("Every cell has a title and a detail, and no stray numbers in them")
    func everyCellSpeaks() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        for cell in layout.cells {
            #expect(!cell.title.isEmpty)
            #expect(!cell.detail.isEmpty)
            // A detail assembled out of a snapshot full of `Double`s is one
            // stray interpolation away from "6.0000001 units of it" — a
            // sentence no screen would ever have shown. Full stops are fine;
            // a full stop with digits on both sides of it is the bug.
            #expect(!Self.hasADecimalPoint(cell.detail), "\(cell.detail)")
            #expect(!Self.hasADecimalPoint(cell.title), "\(cell.title)")
        }
    }

    /// Whether a sentence contains a number nobody could read aloud.
    private static func hasADecimalPoint(_ text: String) -> Bool {
        let characters = Array(text)
        for position in characters.indices where characters[position] == "." {
            guard position > characters.startIndex,
                  position < characters.index(before: characters.endIndex)
            else { continue }
            if characters[position - 1].isNumber, characters[position + 1].isNumber {
                return true
            }
        }
        return false
    }

    @Test("Every region has a title and a detail")
    func everyRegionSpeaks() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        #expect(!layout.regions.isEmpty)

        var covered = 0
        for region in layout.regions {
            #expect(!region.title.isEmpty)
            #expect(!region.detail.isEmpty)
            #expect(region.cellCount > 0)
            #expect(region.firstIndex == covered)
            #expect(layout.cells.indices.contains(region.representativeIndex))
            covered += region.cellCount
        }
        // The bands cover the comb end to end with nothing between them.
        #expect(covered == layout.cells.count)
    }

    @Test("A cell's content tells the interface how to colour it")
    func contentCarriesItsDrawingInformation() {
        #expect(CombCellContent.egg(.worker).stage == .egg)
        #expect(CombCellContent.larva(.worker, daysOld: 2, daysToCapping: 4).stage == .larva)
        #expect(CombCellContent.cappedBrood(.drone, daysToEmergence: 9).stage == .pupa)
        #expect(CombCellContent.stores(.honey).resource == .honey)
        #expect(CombCellContent.stores(.honey).stage == nil)
        #expect(CombCellContent.empty.isEmpty)
        #expect(CombCellContent.egg(.worker).isBrood)
        #expect(!CombCellContent.stores(.pollen).isBrood)
    }

    @Test("A larva's cell reports her own age, not the colony's average")
    func aLarvaKnowsHerOwnAge() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        let larvae = layout.cells.filter { $0.family == .larvae }
        #expect(!larvae.isEmpty)

        var ages: Set<Int> = []
        for cell in larvae {
            guard case .larva(_, let daysOld, let daysToCapping) = cell.content else {
                Issue.record("A larva cell held \(cell.content)")
                continue
            }
            #expect(daysOld >= 0)
            #expect(daysToCapping >= 0)
            ages.insert(daysOld)
        }

        // A month-old colony has larvae of several ages at once. If this ever
        // collapses to one value, the per-cell detail has quietly become an
        // aggregate again.
        #expect(ages.count > 1)
    }

    @Test("Drone brood is drawn in drone comb")
    func droneBroodSitsInDroneCells() {
        let snapshot = establishedSnapshot()
        let layout = CombLayout(snapshot: snapshot)

        for cell in layout.cells {
            switch cell.content {
            case .egg(.drone), .larva(.drone, _, _), .cappedBrood(.drone, _):
                #expect(cell.cellType == .drone)
            case .stores, .empty:
                // The engine keeps a count of drone comb, not a map of it, so
                // a cell with stores in it has no recorded size. Saying
                // "worker" would be a guess printed as a fact.
                #expect(cell.cellType == nil)
            default:
                break
            }
        }
    }

    // MARK: - Queen cells

    @Test("Queen cells appear at the centre, with how long they have left")
    func queenCellsAppear() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(10)
        simulation.mutateWorld { world in
            world.hive.comb.addQueenCell(
                QueenCell(id: EntityID(rawValue: 900_001), purpose: .swarm)
            )
            world.hive.comb.addQueenCell(
                QueenCell(id: EntityID(rawValue: 900_002), purpose: .supersedure)
            )
        }

        let snapshot = simulation.snapshot()
        let layout = CombLayout(snapshot: snapshot)

        #expect(layout.count(of: .queenCells) == 2)

        // They are the first cells drawn, which puts them dead centre.
        #expect(layout.indices(of: .queenCells) == [0, 1])

        for index in layout.indices(of: .queenCells) {
            let cell = layout.cells[index]
            #expect(cell.cellType == .queenCup)
            #expect(!cell.title.isEmpty)
            #expect(!cell.detail.isEmpty)
            guard case .queenCell(let purpose, let days) = cell.content else {
                Issue.record("A queen cell held \(cell.content)")
                continue
            }
            #expect(cell.title == purpose.displayName)
            #expect(days == QueenCell.daysToEmergence)
        }

        #expect(layout.cells[0].content == .queenCell(.swarm, daysToEmergence: 12))
        #expect(layout.regions.first?.family == .queenCells)
    }

    @Test("A colony with no queen cells draws none")
    func noQueenCellsWhenThereAreNone() {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(10)
        simulation.mutateWorld { $0.hive.comb.queenCells.removeAll() }

        let layout = CombLayout(snapshot: simulation.snapshot())
        #expect(layout.count(of: .queenCells) == 0)
        #expect(layout.indices(of: .queenCells).isEmpty)
    }

    // MARK: - Reading it back

    @Test("A cell can be looked up, and a miss is a miss")
    func lookingUpACell() {
        let layout = CombLayout(snapshot: establishedSnapshot())

        #expect(layout.cell(at: 0)?.index == 0)
        #expect(layout.cell(at: nil) == nil)
        #expect(layout.cell(at: -1) == nil)
        #expect(layout.cell(at: layout.cells.count) == nil)
    }

    @Test("The legend lists only what the comb is showing")
    func theLegendMatchesTheComb() {
        let layout = CombLayout(snapshot: establishedSnapshot())

        for family in layout.familiesPresent {
            #expect(layout.count(of: family) > 0)
        }
        for family in CombCellFamily.allCases where !layout.familiesPresent.contains(family) {
            #expect(layout.count(of: family) == 0)
        }
        // The order is the fixed one, not a dictionary's.
        #expect(layout.familiesPresent == CombCellFamily.allCases
            .filter { layout.count(of: $0) > 0 })
    }
}

// MARK: - Geometry

@Suite("Comb geometry")
struct CombGeometryTests {

    @Test("A touch on a cell's middle finds that cell")
    func hitTestFindsEveryCell() {
        let geometry = CombGeometry(cellCount: 200, width: 360, height: 320)

        for index in 0..<200 {
            let middle = geometry.centre(of: index)
            #expect(geometry.index(atX: middle.x, y: middle.y) == index)
        }
    }

    @Test("A touch a little off centre still finds the cell")
    func hitTestToleratesAFinger() {
        let geometry = CombGeometry(cellCount: 61, width: 400, height: 400)
        let nudge = geometry.radius * 0.4

        for index in 0..<61 {
            let middle = geometry.centre(of: index)
            #expect(geometry.index(atX: middle.x + nudge, y: middle.y) == index)
            #expect(geometry.index(atX: middle.x, y: middle.y - nudge) == index)
        }
    }

    @Test("A touch off the comb finds nothing")
    func hitTestMissesTheBackground() {
        let geometry = CombGeometry(cellCount: 19, width: 300, height: 300)

        #expect(geometry.index(atX: -500, y: -500) == nil)
        #expect(geometry.index(atX: 5_000, y: 5_000) == nil)
        #expect(geometry.index(atX: .nan, y: 0) == nil)
    }

    @Test("The whole comb fits inside the canvas")
    func everyCellFitsOnTheCanvas() {
        let width = 360.0
        let height = 313.0
        let geometry = CombGeometry(cellCount: 420, width: width, height: height)

        for index in 0..<420 {
            let middle = geometry.centre(of: index)
            #expect(middle.x - geometry.radius >= -0.001)
            #expect(middle.x + geometry.radius <= width + 0.001)
            #expect(middle.y - geometry.radius >= -0.001)
            #expect(middle.y + geometry.radius <= height + 0.001)
        }
    }

    @Test("Cells wind outward from the middle")
    func theSpiralIsConcentric() {
        let geometry = CombGeometry(cellCount: 91, width: 400, height: 400)

        func distance(_ index: Int) -> Double {
            let point = geometry.centre(of: index)
            let dx = point.x - geometry.originX
            let dy = point.y - geometry.originY
            return (dx * dx + dy * dy).squareRoot()
        }

        #expect(distance(0) < 0.001)

        // Ring by ring: nothing in ring two is nearer the middle than
        // anything in ring one.
        let ringOne = (1...6).map(distance).max() ?? 0
        let ringTwo = (7...18).map(distance).min() ?? 0
        #expect(ringTwo > ringOne)
    }

    @Test("Rings are sized to hold the cells asked for, and no more")
    func ringsHoldWhatIsAskedOf() {
        for count in [1, 2, 7, 8, 19, 20, 61, 62, 900] {
            let rings = CombGeometry.rings(forCellCount: count)
            let capacity = 1 + 3 * rings * (rings + 1)
            #expect(capacity >= count)
            if rings > 0 {
                let smaller = 1 + 3 * (rings - 1) * rings
                #expect(smaller < count)
            }
        }
    }

    @Test("An empty comb is a geometry with nothing in it rather than a crash")
    func anEmptyCombIsHarmless() {
        let geometry = CombGeometry(cellCount: 0, width: 300, height: 300)
        #expect(geometry.cellCount == 0)
        #expect(geometry.radius > 0)
        #expect(geometry.index(atX: 150, y: 150) == nil)
    }
}
