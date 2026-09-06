import Testing
import Foundation
@testable import FlowerPowerCore

/// The decisions the player can make, and the record the colony keeps.
///
/// The rule behind all of them: instinct is the default. A colony with no
/// posture chosen behaves exactly as it did before postures existed, so not
/// answering costs nothing that instinct would not have cost anyway.
@Suite("Decisions")
struct DecisionTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func thriving(seed: UInt64 = 21) -> Simulation {
        Fixture.thrivingSimulation(config: .standard, seed: seed)
    }

    // MARK: - Postures

    @Test("Instinct is the default and holds nothing")
    func instinctIsDefault() {
        let simulation = thriving()
        #expect(simulation.world.posture == .instinct)
        #expect(simulation.world.postureUntilDay == nil)
    }

    @Test("A posture expires on its own")
    func postureExpires() {
        var simulation = thriving()
        simulation.adoptPosture(.holdEntrance, forDays: 2)
        #expect(simulation.world.posture == .holdEntrance)

        for _ in 0..<3 { _ = simulation.stepDay() }
        #expect(simulation.world.posture == .instinct)
        #expect(simulation.world.postureUntilDay == nil)
    }

    @Test("Holding the entrance costs foraging")
    func postureCostsForage() {
        var held = thriving()
        var free = thriving()
        held.adoptPosture(.holdEntrance, forDays: 10)

        for _ in 0..<5 {
            _ = held.stepDay()
            _ = free.stepDay()
            held.forceWeather(sky: .clear, temperature: 22)
            free.forceWeather(sky: .clear, temperature: 22)
        }

        #expect(
            held.world.averageNectarIntake < free.world.averageNectarIntake,
            "a colony at the door is not at the flowers"
        )
    }

    @Test("Each attack style offers the postures that can help it", arguments: [
        (AttackStyle.entrance, HivePosture.holdEntrance),
        (.pilfer, .narrowEntrance),
        (.field, .foragersHome),
        (.comb, .cleanersOut)
    ])
    func optionsPerStyle(style: AttackStyle, expected: HivePosture) {
        #expect(HivePosture.options(against: style).contains(expected))
        #expect(HivePosture.options(against: style).contains(.instinct),
                "doing nothing is always on the list")
    }

    @Test("A bear offers no decision, because there is none")
    func catastropheHasNoWindow() {
        #expect(HivePosture.options(against: .catastrophic).isEmpty)
        #expect(!Predator.bear.hasDecisionWindow)
        #expect(Predator.wasp.hasDecisionWindow)
    }

    // MARK: - Threat windows

    @Test("A siege opens a window and resolves when it closes")
    func siegeWindow() {
        var simulation = thriving()
        let threat = ActiveThreat(
            predator: .wasp, beganOnDay: simulation.day,
            resolvesOnDay: simulation.day + 2
        )
        simulation.mutateWorld { $0.activeThreat = threat }

        _ = simulation.stepDay()
        #expect(simulation.world.activeThreat == threat, "still open the next day")

        var ended = false
        for _ in 0..<2 {
            for event in simulation.stepDay() {
                if case .threatEnded(.wasp) = event { ended = true }
            }
        }
        #expect(ended)
        #expect(simulation.world.activeThreat == nil)
    }

    @Test("Responding to a siege holds the posture until it resolves")
    func respondToSiege() {
        var simulation = thriving()
        let threat = ActiveThreat(
            predator: .wasp, beganOnDay: simulation.day,
            resolvesOnDay: simulation.day + 2
        )
        simulation.mutateWorld { $0.activeThreat = threat }

        simulation.respond(to: threat, with: .holdEntrance)
        #expect(simulation.world.posture == .holdEntrance)
        #expect(simulation.world.postureUntilDay ?? 0 >= threat.resolvesOnDay)
    }

    @Test("Responding to a siege that is over does nothing")
    func staleResponse() {
        var simulation = thriving()
        let stale = ActiveThreat(predator: .wasp, beganOnDay: 0, resolvesOnDay: 1)
        simulation.respond(to: stale, with: .holdEntrance)
        #expect(simulation.world.posture == .instinct)
    }

    /// Measured over many sieges rather than one: defence is a dice roll, and
    /// the posture changes the odds rather than the outcome.
    @Test("Holding the entrance repels more wasps")
    func holdingRepelsMore() {
        func repelled(posture: HivePosture) -> Int {
            var count = 0
            for seed in 0..<40 {
                var simulation = thriving(seed: UInt64(300 + seed))
                simulation.mutateWorld {
                    $0.activeThreat = ActiveThreat(
                        predator: .wasp, beganOnDay: 0, resolvesOnDay: 1
                    )
                    $0.posture = posture
                    $0.postureUntilDay = 5
                }
                for event in simulation.stepDay() + simulation.stepDay() {
                    if case .attackRepelled(.wasp) = event { count += 1 }
                }
            }
            return count
        }

        let held = repelled(posture: .holdEntrance)
        let instinct = repelled(posture: .instinct)
        #expect(held > instinct, "held \(held), instinct \(instinct)")
    }

    // MARK: - Absconding

    @Test("Relocation is absconding: adults go, everything else stays")
    func relocationAbsconds() {
        var simulation = thriving()
        for _ in 0..<20 { _ = simulation.stepDay() }
        let adults = simulation.hive.adultCount
        #expect(simulation.hive.broodCount > 0)

        simulation.relocate(to: HiveLocation(type: .cave))

        #expect(simulation.hive.adultCount == adults)
        #expect(simulation.hive.broodCount == 0)
        #expect(simulation.hive.comb.builtCells == 0)
        #expect(simulation.hive.location.type == .cave)
        #expect(simulation.hive.resources[.honey] <= Double(adults) * SimulationConfig.standard.honeyCarriedPerSwarmBee + 0.001)
    }

    // MARK: - Swarming

    @Test("The first swarm cell opens the window")
    func swarmWindowOpens() {
        var simulation = thriving()
        var announced: Int?
        simulation.mutateWorld { world in
            world.hive.comb.addQueenCell(QueenCell(id: EntityID(rawValue: 9_001), purpose: .swarm))
        }
        // The window is set where the cell is started, so drive that path.
        let today = simulation.day
        simulation.mutateWorld { world in
            world.pendingSwarm = PendingSwarm(startedOnDay: today, departsOnDay: today + 8)
        }
        for event in simulation.stepDay() {
            if case .swarmPreparing(let day) = event { announced = day }
        }
        _ = announced
        #expect(simulation.world.pendingSwarm != nil)
        #expect(simulation.world.pendingSwarm?.daysRemaining(on: simulation.day) ?? 0 <= 8)
    }

    @Test("Discouraging a swarm adopts the make-room posture")
    func discourage() {
        var simulation = thriving()
        simulation.mutateWorld {
            $0.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        simulation.discourageSwarm()

        #expect(simulation.world.pendingSwarm?.discouraged == true)
        #expect(simulation.world.posture == .makeRoom)
    }

    // MARK: - Answering congestion with space

    /// A colony big enough to be worth dividing, with its adults spread across
    /// the whole age range so "youngest first" and "oldest first" mean
    /// different things.
    private func crowded(
        seed: UInt64 = 21,
        adults: Int = 200,
        site: HiveLocationType = .livingTreeCavity
    ) -> Simulation {
        var simulation = Fixture.thrivingSimulation(
            config: .standard, seed: seed, locationType: site
        )
        simulation.mutateWorld { world in
            world.hive.bees.append(contentsOf: (0..<adults).map { index in
                Bee(
                    id: EntityID(rawValue: UInt64(70_000 + index)),
                    kind: .worker, stage: .adult,
                    daysInStage: index % 30
                )
            })
        }
        return simulation
    }

    /// A crowded colony that has also drawn every cell of its cavity, with
    /// honey to pay for more. Everything below about the *site's* room needs
    /// this: a colony with cavity still to draw takes the free cavity first,
    /// which is correct and makes it a poor test of the extension.
    private func fullyDrawn(
        site: HiveLocationType = .livingTreeCavity,
        honey: Double = 20_000
    ) -> Simulation {
        var simulation = crowded(site: site)
        simulation.mutateWorld { world in
            let capacity = world.hive.comb.capacity
            world.hive.comb = Comb(workerCells: capacity, droneCells: 0, capacity: capacity)
            world.hive.resources.add(honey, of: .honey)
        }
        return simulation
    }

    private func adultAges(_ simulation: Simulation) -> [Int] {
        simulation.hive.bees
            .filter { $0.kind == .worker && $0.isAdult }
            .map(\.daysInStage)
    }

    // MARK: Adding comb

    /// Where the room comes from is decided by where the bees settled, months
    /// before anybody asks the question.
    @Test("Only some sites have room to give")
    func extensionRoomIsASiteProperty() {
        #expect(HiveLocationType.cliff.extensionRoom == 0, "rock is rock")
        #expect(HiveLocationType.nestbox.extensionRoom > 1, "a box takes another box")
        #expect(HiveLocationType.livingTreeCavity.extensionRoom > 0)
        #expect(HiveLocationType.livingTreeCavity.extensionRoom
                < HiveLocationType.insideWalls.extensionRoom,
                "heartwood rot spreads slower than a wall cavity runs")
    }

    @Test("With the cavity drawn out, adding comb enlarges it")
    func addCombEnlarges() {
        var simulation = fullyDrawn()
        let before = simulation.hive.comb.capacity
        #expect(simulation.hive.comb.freeCapacity == 0)

        let added = simulation.addComb()

        #expect(added > 0)
        #expect(simulation.hive.comb.capacity == before + added)
        #expect(simulation.hive.maximumCells == before + added)
    }

    /// A colony in a cliff face can still be given comb while it has cavity to
    /// draw into. What it cannot be given is *more cavity* — that is rock.
    @Test("A site with no room to give cannot be extended")
    func addCombOnRock() {
        var simulation = fullyDrawn(site: .cliff)

        #expect(simulation.combExtensionRemaining == 0)
        #expect(simulation.canAddComb == false, "no free cavity and no more rock to take")
        let added = simulation.addComb()
        #expect(added == 0)
        #expect(simulation.hive.comb.capacity == HiveLocationType.cliff.maximumCells)
    }

    /// It runs out, which is what stops it being an answer to everything.
    ///
    /// A nestbox rather than a tree cavity, because a nestbox is the site with
    /// real room to give — a beekeeper puts another box on it — so the
    /// decision is one that can be taken several times before the site says no.
    @Test("The room a site has is finite")
    func addCombRunsOut() {
        // Every cell drawn and honey to burn, so the only limit left is the
        // site itself rather than the larder or the comb.
        var simulation = fullyDrawn(site: .nestbox)

        var additions = 0
        while simulation.addComb() > 0 {
            additions += 1
            #expect(additions < 100, "addComb never stopped")
        }

        #expect(additions > 1, "worth taking more than once")
        #expect(simulation.canAddComb == false)

        let natural = Double(HiveLocationType.nestbox.maximumCells)
        let ceiling = natural * (1 + HiveLocationType.nestbox.extensionRoom)
        #expect(Double(simulation.hive.comb.capacity) <= ceiling + 0.5)
    }

    /// The measured heart of the mechanic.
    ///
    /// The first version of `addComb` gave the colony *room* and let
    /// `ConstructionSystem` fill it, which measured at exactly nothing: over 60
    /// colonies and two years it never fired, and when the trigger was loosened
    /// until it did, swarming was unmoved. `swarmPressure` runs on
    /// `combOccupancy` — cells used over cells *drawn* — and empty cavity is
    /// not in that ratio. So it gives drawn comb, and charges the honey the wax
    /// would have cost. Which is why beekeepers hoard drawn comb.
    @Test("Adding comb gives drawn comb, and charges honey for it")
    func addCombDrawsComb() {
        var simulation = crowded()
        simulation.mutateWorld { $0.hive.resources.add(400, of: .honey) }

        let combBefore = simulation.hive.comb.builtCells
        let honeyBefore = simulation.hive.resources[.honey]
        let occupancyBefore = simulation.hive.combOccupancy

        let drawn = simulation.addComb()

        #expect(drawn > 0)
        #expect(simulation.hive.comb.builtCells == combBefore + drawn)

        let spent = honeyBefore - simulation.hive.resources[.honey]
        #expect(abs(spent - Double(drawn) * simulation.honeyPerDrawnCell) < 0.001)

        // And the thing it is all for: the nest is less crowded than it was.
        #expect(simulation.hive.combOccupancy < occupancyBefore)
    }

    /// Wax is made from honey at seven to one, so a colony with nothing spare
    /// cannot be given comb however much room the site has.
    @Test("A colony with no honey to spare cannot be given comb")
    func addCombNeedsHoney() {
        var simulation = crowded()
        simulation.mutateWorld { world in
            world.hive.resources = ResourcePool()
            world.hive.resources.add(SimulationConfig.standard.buildHoneyReserve, of: .honey)
        }

        #expect(simulation.canAddComb, "the site still has room")
        #expect(simulation.canAffordComb == false, "but the bees cannot pay for the wax")
        let drawn = simulation.addComb()
        #expect(drawn == 0)
    }

    /// Cavity the colony has not drawn out yet is free. What was stopping the
    /// bees using it was the honey, and that is what is being paid — so there
    /// is no reason to spend the site's finite room on it as well.
    @Test("Cavity the colony already has is used before the site's room")
    func addCombUsesFreeCavityFirst() {
        var simulation = crowded()
        simulation.mutateWorld { $0.hive.resources.add(400, of: .honey) }

        #expect(simulation.hive.comb.freeCapacity > 0)
        let roomBefore = simulation.combExtensionRemaining

        let drawn = simulation.addComb()

        #expect(drawn > 0)
        #expect(simulation.combExtensionRemaining == roomBefore,
                "the tree was not hollowed further to hold comb it had room for")
    }

    /// The difference from `discourageSwarm`: both change the odds, but only
    /// one of them holds the foragers back to do it.
    @Test("Adding comb discourages a swarm without grounding the foragers")
    func addCombDiscouragesWithoutPosture() {
        var simulation = fullyDrawn()
        simulation.mutateWorld {
            $0.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }

        simulation.addComb()

        #expect(simulation.world.pendingSwarm?.discouraged == true)
        #expect(simulation.world.posture == .instinct, "space costs stores, not a flow")
    }

    /// A colony that absconds takes nothing with it, least of all the hole it
    /// was living in.
    @Test("Moving house resets the room that was added")
    func relocatingForgetsTheExtension() {
        var simulation = fullyDrawn()
        simulation.addComb()
        #expect(simulation.hive.comb.capacity > HiveLocationType.livingTreeCavity.maximumCells)

        simulation.relocate(to: HiveLocation(type: .livingTreeCavity))

        #expect(simulation.hive.comb.capacity == HiveLocationType.livingTreeCavity.maximumCells)
        #expect(simulation.canAddComb)
    }

    @Test("The almanac records the nest being opened up")
    func addCombIsChronicled() {
        var simulation = fullyDrawn()
        simulation.addComb()
        #expect(simulation.world.almanac.entries.contains { $0.text.contains("opened up") })
    }

    // MARK: Dividing on purpose

    @Test("A division needs a laying queen and enough bees to make two colonies")
    func canSplitRequirements() {
        #expect(crowded().canSplit)

        var small = Fixture.thrivingSimulation(config: .standard, seed: 21)
        #expect(small.hive.adultWorkerCount < SimulationConfig.standard.swarmMinimumPopulation)
        #expect(small.canSplit == false)
        let refused = small.split()
        #expect(refused == false)

        var queenless = crowded()
        queenless.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
        }
        #expect(queenless.canSplit == false)
    }

    @Test("A split sends the queen and a share of the bees")
    func splitSendsTheQueen() throws {
        var simulation = crowded()
        let adultsBefore = simulation.hive.adultWorkerCount

        let divided = simulation.split()
        #expect(divided)

        let swarm = try #require(simulation.world.lastSwarm)
        let expected = Int(Double(adultsBefore) * SimulationConfig.standard.splitDepartureShare)
        #expect(swarm.workers.count == expected)
        #expect(swarm.queen.kind == .queen)
        #expect(simulation.hive.isQueenright == false, "the queen went with them")
        #expect(simulation.hive.adultWorkerCount == adultsBefore - expected)
    }

    /// The line that makes a split worth doing. A swarm takes the oldest
    /// workers — the entire flying workforce — which is why a swarmed colony
    /// stops gathering. Moving the queen sends the house bees instead.
    @Test("A split takes the house bees and leaves the foragers")
    func splitLeavesTheForagers() {
        var simulation = crowded()
        let before = adultAges(simulation)
        let oldestBefore = before.max() ?? 0
        let meanBefore = Double(before.reduce(0, +)) / Double(before.count)

        let divided = simulation.split()
        #expect(divided)

        let after = adultAges(simulation)
        let meanAfter = Double(after.reduce(0, +)) / Double(after.count)

        #expect(after.max() == oldestBefore, "the oldest bees are still here")
        #expect(meanAfter > meanBefore, "what left was younger than what stayed")
        #expect(simulation.hive.count(performing: .foragingBee) > 0)
    }

    /// A swarm leaves every cell standing, which is where afterswarms come
    /// from — the second and third swarms that finish what the first started.
    @Test("A split keeps one queen cell and tears the rest down")
    func splitKeepsOneCell() {
        var simulation = crowded()
        simulation.mutateWorld { world in
            for index in 0..<4 {
                var cell = QueenCell(
                    id: EntityID(rawValue: UInt64(80_000 + index)), purpose: .swarm
                )
                for _ in 0..<index { cell.advanceOneDay() }
                world.hive.comb.addQueenCell(cell)
            }
            world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }

        let divided = simulation.split()
        #expect(divided)

        #expect(simulation.hive.comb.queenCells.count == 1)
        #expect(simulation.hive.comb.queenCells.first?.daysDeveloped == 3,
                "the best-developed cell is the one kept")
        #expect(simulation.world.pendingSwarm == nil, "the impulse is answered")
    }

    /// The half that leaves is a departed swarm like any other, so the same
    /// three answers apply: follow it, give it away, or let it go.
    @Test("The half that leaves can be followed")
    func splitCanBeFollowed() throws {
        var simulation = crowded()
        let divided = simulation.split()
        #expect(divided)

        let followed = try #require(simulation.followingSwarm(
            to: HiveLocation(type: .nestbox), startingAt: epoch, seed: 11
        ))

        #expect(followed.hive.isQueenright)
        #expect(followed.hive.queenIsMated, "she is the old queen, already mated")
        #expect(followed.hive.adultCount == simulation.world.lastSwarm!.workers.count + 1)
        #expect(followed.patches.count == simulation.patches.count, "the garden comes too")
    }

    /// She did not disappear; she was moved. Without this the reconciliation
    /// in `LineageSystem` would write her off as lost on the next tick.
    @Test("The queen who leaves with a split is recorded as having left")
    func splitRecordsTheQueen() throws {
        var simulation = crowded()
        let reigning = try #require(simulation.world.lineage.reigning)

        let divided = simulation.split()
        #expect(divided)

        let record = try #require(
            simulation.world.lineage.queens.first { $0.number == reigning.number }
        )
        #expect(record.ending == .leftWithSwarm)
        #expect(record.isReigning == false)
    }

    @Test("A division is written into the almanac")
    func splitIsChronicled() {
        var simulation = crowded()
        simulation.split()
        #expect(simulation.world.almanac.entries.contains { $0.text.contains("divided on purpose") })
    }

    /// Instinct is the default and stays it. A player who never answers gets
    /// exactly the colony they got before either of these existed.
    @Test("Neither answer is taken on the colony's behalf")
    func instinctIsUntouched() {
        var simulation = crowded()
        let capacity = simulation.hive.comb.capacity
        let adults = simulation.hive.adultWorkerCount

        for _ in 0..<20 { _ = simulation.stepDay() }

        #expect(simulation.hive.comb.capacity == capacity, "nothing opened the nest up")
        #expect(simulation.world.posture == .instinct)
        #expect(simulation.hive.adultWorkerCount > 0)
        #expect(adults > 0)
    }

    @Test("Discouraging with no swarm pending does nothing")
    func discourageNothing() {
        var simulation = thriving()
        simulation.discourageSwarm()
        #expect(simulation.world.posture == .instinct)
    }

    /// The swarm that leaves is kept so the player may go with it, and the
    /// colony it founds starts exactly as a real swarm does.
    @Test("Following the swarm founds a colony from it")
    func followTheSwarm() throws {
        var simulation = thriving()
        let workers = (0..<40).map { index in
            Bee(id: EntityID(rawValue: UInt64(50_000 + index)), kind: .worker,
                stage: .adult, daysInStage: 25)
        }
        let queen = try #require(simulation.hive.queen)
        simulation.mutateWorld { world in
            world.lastSwarm = DepartedSwarm(
                day: world.hive.bees.count, queen: queen, workers: workers,
                genetics: world.hive.genetics, honeyCarried: 5,
                queenNumber: world.lineage.reigning?.number
            )
        }

        let followed = try #require(simulation.followingSwarm(
            to: HiveLocation(type: .cave), startingAt: epoch, seed: 5
        ))

        #expect(followed.hive.adultCount == 41)
        #expect(followed.hive.isQueenright)
        #expect(followed.hive.queenIsMated)
        #expect(followed.hive.broodCount == 0)
        #expect(followed.hive.comb.builtCells == 0)
        #expect(abs(followed.hive.resources[.honey] - 5) < 0.001)
        #expect(followed.patches.count == simulation.patches.count, "the garden comes too")
        #expect(followed.world.lineage.generation == simulation.world.lineage.generation + 1)
        #expect(followed.world.lineage.reigning?.number == simulation.world.lineage.reigning?.number,
                "she keeps her number")

        let ids = followed.hive.bees.map(\.id)
        #expect(Set(ids).count == ids.count, "fresh identifiers, no collisions")
    }

    // MARK: - Entrance

    @Test("Instinct seals the entrance in autumn when there is propolis")
    func instinctSeals() {
        var simulation = thriving()
        // Late autumn: instinct waits until the last flow is nearly over.
        simulation.clock = SimClock(epoch: epoch, tick: (180 + 70) * SimClock.ticksPerDay)
        simulation.mutateWorld { $0.hive.resources.add(20, of: .propolis) }

        var sealed = false
        for _ in 0..<3 {
            for event in simulation.stepDay() {
                if case .entranceSealed(true) = event { sealed = true }
            }
        }
        #expect(sealed)
        #expect(simulation.world.entranceSealed)
    }

    @Test("The player can keep it open")
    func keepOpen() {
        var simulation = thriving()
        simulation.clock = SimClock(epoch: epoch, tick: (180 + 70) * SimClock.ticksPerDay)
        simulation.mutateWorld { $0.hive.resources.add(20, of: .propolis) }
        simulation.decideEntrance(sealed: false)

        for _ in 0..<5 { _ = simulation.stepDay() }
        #expect(!simulation.world.entranceSealed)
    }

    @Test("Spring opens it again and resets the decision")
    func springOpens() {
        var simulation = thriving()
        simulation.clock = SimClock(epoch: epoch, tick: 360 * SimClock.ticksPerDay)
        simulation.mutateWorld {
            $0.entranceSealed = true
            $0.entranceDecision = true
        }
        for _ in 0..<12 { _ = simulation.stepDay() }
        #expect(!simulation.world.entranceSealed)
        #expect(simulation.world.entranceDecision == nil)
    }

    // MARK: - Honey

    @Test("Honey can be taken only from what the colony can spare")
    func takeHoney() {
        var simulation = thriving()
        simulation.mutateWorld { $0.hive.resources.add(400, of: .honey) }
        let spare = simulation.harvestableHoney
        #expect(spare > 0)

        let taken = simulation.takeHoney(10_000)
        #expect(abs(taken - spare) < 0.001, "capped at what can be spared")
        #expect(abs(simulation.world.honeyTaken - taken) < 0.001)
        #expect(simulation.harvestableHoney < 0.001)
    }

    @Test("A colony with nothing to spare gives nothing")
    func takeNothing() {
        var simulation = thriving()
        simulation.mutateWorld { $0.hive.resources = ResourcePool() }
        #expect(simulation.takeHoney(50) == 0)
    }

    // MARK: - Lineage

    @Test("A founded colony has Queen I, mated")
    func foundingQueen() {
        let simulation = Simulation.newGame(at: HiveLocation(type: .cave), startingAt: epoch, seed: 1)
        let queen = simulation.world.lineage.reigning
        #expect(queen?.number == 1)
        #expect(queen?.title == "Queen I")
        #expect(queen?.matedOnDay == 0)
        #expect(simulation.world.lineage.generation == 1)
    }

    @Test("Roman numerals", arguments: [(1, "I"), (4, "IV"), (9, "IX"), (14, "XIV"), (40, "XL")])
    func roman(value: Int, expected: String) {
        #expect(QueenRecord.roman(value) == expected)
    }

    @Test("A queen who leaves with a swarm is recorded as such")
    func lineageRecordsSwarm() {
        var lineage = Lineage()
        lineage.found(onDay: 0, patrilines: 12)
        lineage.end(onDay: 100, .leftWithSwarm)
        let daughter = lineage.crown(onDay: 108, quality: 0.9)

        #expect(lineage.queens.first?.ending == .leftWithSwarm)
        #expect(daughter.number == 2)
        #expect(daughter.motherNumber == 1)
        #expect(lineage.reigning?.number == 2)
    }

    @Test("Naming a queen trims and caps the name")
    func naming() {
        var lineage = Lineage()
        lineage.found(onDay: 0, patrilines: 12)
        lineage.name(1, "  Boudicca  ")
        #expect(lineage.queens[0].title == "Boudicca")
        lineage.name(1, "   ")
        #expect(lineage.queens[0].title == "Queen I")
    }

    @Test("The lineage follows the simulation's queen events")
    func lineageFromEvents() {
        var simulation = thriving()
        for _ in 0..<10 { _ = simulation.stepDay() }
        // Kill the queen and leave the colony a clutch of young worker larvae
        // to graft from. The fixture's own brood nest at this age is a few
        // larvae on the point of capping, and a larva that is capped the day
        // the queen goes is already too old to become one; traced once, the
        // colony sat queenless with nothing to rear and never started a cell.
        simulation.mutateWorld { world in
            world.hive.bees.removeAll { $0.kind == .queen }
            for offset in 0..<12 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: 900_000 + UInt64(offset)),
                    kind: .worker,
                    stage: .larva,
                    daysInStage: offset % 2
                ))
            }
        }
        for _ in 0..<45 { _ = simulation.stepDay() }

        #expect(simulation.world.lineage.count >= 2, "a successor should have been crowned")
        #expect(simulation.world.lineage.queens.first?.isReigning == false)
    }

    // MARK: - Almanac

    @Test("The almanac writes one line per event kind per day")
    func almanacDedupes() {
        var almanac = Almanac()
        let lineage = Lineage()
        almanac.chronicle([.attacked(.wasp), .attacked(.wasp), .threatBegan(.wasp, resolvesOnDay: 2)],
                          day: 5, honey: 10, lineage: lineage)
        almanac.chronicle([.threatBegan(.wasp, resolvesOnDay: 2)], day: 5, honey: 10, lineage: lineage)

        #expect(almanac.entries.count == 1)
        #expect(almanac.entries.first?.text == "Wasp at the nest.")
    }

    @Test("The almanac marks the seasons and the honey peak")
    func almanacSeasons() {
        var almanac = Almanac()
        let lineage = Lineage()
        almanac.chronicle([], day: 0, honey: 10, lineage: lineage)
        almanac.chronicle([], day: 90, honey: 100, lineage: lineage)
        almanac.chronicle([], day: 91, honey: 150, lineage: lineage)

        let texts = almanac.entries.map(\.text)
        #expect(texts.contains("Spring begins."))
        #expect(texts.contains("Summer begins."))
        #expect(texts.contains { $0.hasPrefix("Stores reach a new high") })
    }

    @Test("The almanac is capped")
    func almanacCap() {
        var almanac = Almanac()
        let lineage = Lineage()
        for day in 0..<(Almanac.limit + 50) {
            almanac.chronicle([.nectarFlowBegan], day: day, honey: 0, lineage: lineage)
        }
        #expect(almanac.entries.count == Almanac.limit)
    }

    @Test("A simulated colony writes its own almanac")
    func almanacFromSimulation() {
        var simulation = thriving()
        for _ in 0..<95 { _ = simulation.stepDay() }
        #expect(!simulation.world.almanac.isEmpty)
        #expect(simulation.world.almanac.entries.contains { $0.text == "Summer begins." })
    }

    // MARK: - The seasonal clock

    @Test("Winter ticks are shorter")
    func winterFaster() {
        let clock = SimClock(epoch: epoch, winterSpeed: 2)
        let springTick = 10 * SimClock.ticksPerDay
        let winterTick = 280 * SimClock.ticksPerDay
        #expect(clock.seconds(forTick: springTick) == SimClock.defaultRealSecondsPerTick)
        #expect(clock.seconds(forTick: winterTick) == SimClock.defaultRealSecondsPerTick / 2)
    }

    @Test("Catch-up walks the seasonal rate exactly")
    func catchUpAcrossWinter() {
        var simulation = Simulation.newGame(at: HiveLocation(type: .cave), startingAt: epoch, seed: 2)
        simulation.winterSpeed = 2
        // Lifted so the whole stretch, winter included, is simulated in one
        // catch-up rather than capped at the ceiling.
        simulation.catchUpCeilingDays = 400
        let target = simulation.date(afterSimulatedDays: 300)
        let report = simulation.advance(to: target)
        #expect(report.daysSimulated == 300)
        #expect(simulation.day == 300)
    }

    @Test("A uniform clock is unchanged by the seasonal one")
    func uniformUnchanged() {
        let clock = SimClock(epoch: epoch, winterSpeed: 1)
        let date = epoch.addingTimeInterval(Double(300 * SimClock.ticksPerDay) * SimClock.defaultRealSecondsPerTick)
        #expect(clock.pendingTicks(at: date) == min(300, SimClock.defaultMaxCatchUpDays) * SimClock.ticksPerDay)
    }

    /// Saves from before the seasonal clock carry neither field, and they
    /// were written under a uniform rate: they must decode as uniform, or the
    /// date-to-tick mapping they were saved under stops holding.
    @Test("An old save decodes as a uniform clock")
    func oldClockDecodes() throws {
        let json = """
        {"epoch":\(epoch.timeIntervalSinceReferenceDate),"tick":480,"realSecondsPerTick":300,"maxCatchUpDays":180}
        """
        let clock = try JSONDecoder().decode(SimClock.self, from: Data(json.utf8))
        #expect(clock.winterSpeed == 1)
        #expect(clock.tick == 480)
        #expect(clock.realSecondsAtTick == 480 * 300)
    }

    @Test("A modern clock round-trips")
    func clockRoundTrip() throws {
        var clock = SimClock(epoch: epoch, winterSpeed: 2)
        for _ in 0..<(275 * SimClock.ticksPerDay) { clock.commitTick() }
        let data = try JSONEncoder().encode(clock)
        let restored = try JSONDecoder().decode(SimClock.self, from: data)
        #expect(restored == clock)
        #expect(restored.date(atTick: restored.tick + 24) == clock.date(atTick: clock.tick + 24))
    }
}
