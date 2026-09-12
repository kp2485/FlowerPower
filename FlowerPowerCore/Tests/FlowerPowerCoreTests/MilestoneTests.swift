import Testing
import Foundation
@testable import FlowerPowerCore

/// The colony's firsts.
///
/// Three things have to hold, and they are in decreasing order of how much
/// trouble getting them wrong would cause.
///
/// 1. `MilestoneSystem` must not change the simulation. It is appended to the
///    end of the pipeline of a game whose balance baseline reproduces byte for
///    byte, and a badge that costs a colony one random draw would invalidate
///    every measured number in `PLAN.md`.
/// 2. A milestone is awarded once and never again, however long its condition
///    stays true — otherwise a colony over two hundred bees emits a badge every
///    hour for a year.
/// 3. Every case says something, in four places: a title, a sentence, a
///    narration line and a symbol. An exhaustive `switch` is quite happy to
///    return "".
@Suite("Milestones")
struct MilestoneTests {

    // MARK: - Fixtures

    /// A world placed directly in the state a condition is about, rather than
    /// one simulated into it.
    ///
    /// Reaching "five hundred adults" or "ten raids driven off" by running a
    /// colony is luck rather than testing — the same argument `ColonyNews.Facts`
    /// makes for itself. The conditions are pure functions of the world, the
    /// events and the day, so they can be stated directly.
    private func world(patches: Int = 0) -> World {
        var ids = IDGenerator()
        var world = World(hive: Hive.newColony(at: HiveLocation(type: .livingTreeCavity), ids: &ids))
        for index in 0..<patches {
            world.patches.append(FlowerPatch(
                id: ids.next(),
                photoLocalIdentifier: "p\(index)",
                species: Fixture.palette[index % Fixture.palette.count],
                identificationConfidence: 0.9,
                coordinate: nil,
                distanceMetres: 400,
                discoveredAt: epoch,
                registeredOnDay: 0
            ))
        }
        return world
    }

    private func isMet(
        _ milestone: Milestone,
        _ world: World,
        events: [SimEvent] = [],
        day: Int = 0
    ) -> Bool {
        MilestoneSystem.isMet(milestone, world, events, day: day)
    }

    /// Runs the system over a world as the pipeline would, returning the
    /// events it emitted.
    private func run(_ world: inout World, events: [SimEvent] = [], day: Int = 0) -> [SimEvent] {
        var context = TickContext(
            clock: SimClock(epoch: epoch, tick: day * SimClock.ticksPerDay),
            config: .standard,
            rng: SeededRandom(seed: 1),
            ids: IDGenerator()
        )
        for event in events { context.emit(event) }
        MilestoneSystem().update(&world, &context)
        return context.events.filter { if case .milestone = $0 { true } else { false } }
    }

    // MARK: - The vocabulary

    @Test("Every milestone has a title, a sentence and a symbol")
    func everyCaseSpeaks() {
        for milestone in Milestone.allCases {
            #expect(!milestone.title.isEmpty, "\(milestone) has no title")
            #expect(!milestone.detail.isEmpty, "\(milestone) has no detail")
            #expect(milestone.detail.hasSuffix("."), "\(milestone) reads as a fragment")
            #expect(milestone.detail.count > 25, "\(milestone) says very little")
            #expect(!milestone.symbolName.isEmpty, "\(milestone) has no symbol")
            #expect(!milestone.symbolName.contains(" "),
                    "\(milestone) symbol '\(milestone.symbolName)' has a space")

            let narration = SimEvent.milestone(milestone).narration
            #expect(narration.contains(milestone.title.lowercased()),
                    "\(milestone) narrates without naming itself")
            #expect(narration.hasSuffix("."))
        }
    }

    @Test("The badges are distinguishable from one another")
    func noDuplicates() {
        // A grid of two dozen badges is only readable if they do not share a
        // face, and a copy-pasted `case` is the easy way to give two of them
        // the same one.
        #expect(Set(Milestone.allCases.map(\.title)).count == Milestone.allCases.count)
        #expect(Set(Milestone.allCases.map(\.detail)).count == Milestone.allCases.count)
        #expect(Set(Milestone.allCases.map(\.symbolName)).count == Milestone.allCases.count)
        #expect(Set(Milestone.allCases.map(\.rawValue)).count == Milestone.allCases.count)
    }

    @Test("A milestone is a highlight, and never louder than a warning")
    func eventShape() {
        let event = SimEvent.milestone(.firstSwarm)
        #expect(event.isHighlight)
        #expect(event.severity == .notable)
        #expect(event.severity < .warning)
    }

    // MARK: - The record itself

    @Test("The record answers what it holds and when")
    func recordBasics() {
        var milestones = Milestones()
        #expect(milestones.isEmpty)
        #expect(milestones.count == 0)
        #expect(milestones.remaining.count == Milestone.allCases.count)

        let awarded = milestones.award(.firstFlower, onDay: 3)
        #expect(awarded)
        #expect(milestones.has(.firstFlower))
        #expect(milestones.day(of: .firstFlower) == 3)
        #expect(milestones.day(of: .tenFlowers) == nil)
        #expect(milestones.count == 1)
        #expect(!milestones.remaining.contains(.firstFlower))

        // Awarding it again is a no-op, day and all — a badge records the day
        // of the first time, not the most recent one.
        let again = milestones.award(.firstFlower, onDay: 99)
        #expect(again == false)
        #expect(milestones.day(of: .firstFlower) == 3)
        #expect(milestones.count == 1)
    }

    @Test("A record kept in arrival order survives a round trip")
    func recordCodable() throws {
        var milestones = Milestones()
        milestones.award(.firstBrood, onDay: 21)
        milestones.award(.firstFlower, onDay: 2)

        let data = try JSONEncoder().encode(milestones)
        let restored = try JSONDecoder().decode(Milestones.self, from: data)

        #expect(restored == milestones)
        #expect(restored.achieved.map(\.milestone) == [.firstBrood, .firstFlower])
    }

    /// A save written by a build that knew a milestone this one does not must
    /// still open. Losing a badge is acceptable; losing the colony is not.
    @Test("An unrecognised milestone in a save is dropped, not thrown")
    func recordToleratesAnUnknownCase() throws {
        let json = Data("""
        {"achieved":[{"milestone":"firstFlower","day":4},
                     {"milestone":"aBadgeFromTheFuture","day":9}]}
        """.utf8)

        let restored = try JSONDecoder().decode(Milestones.self, from: json)
        #expect(restored.count == 1)
        #expect(restored.day(of: .firstFlower) == 4)
    }

    // MARK: - Old saves

    @Test("A world saved before milestones existed still decodes")
    func oldSavesDecode() throws {
        let encoded = try JSONEncoder().encode(world(patches: 2))
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["milestones"] != nil, "the fixture never had the key to remove")
        object.removeValue(forKey: "milestones")

        let stripped = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(World.self, from: stripped)

        #expect(restored.milestones.isEmpty)
        #expect(restored.patches.count == 2, "the rest of the world came back too")
    }

    // MARK: - Conditions read from the world

    @Test("The garden's milestones are counted from the patches")
    func gardenConditions() {
        #expect(!isMet(.firstFlower, world()))
        #expect(isMet(.firstFlower, world(patches: 1)))
        #expect(!isMet(.tenFlowers, world(patches: 9)))
        #expect(isMet(.tenFlowers, world(patches: 10)))

        // The palette is six species across five families, so five is reached
        // and ten is not.
        #expect(isMet(.placedToFamily, world(patches: 1)))
        #expect(isMet(.fiveFamilies, world(patches: 12)))
        #expect(!isMet(.tenFamilies, world(patches: 12)))

        var unidentified = world()
        unidentified.patches.append(FlowerPatch(
            id: EntityID(rawValue: 900),
            photoLocalIdentifier: "mystery",
            species: nil,
            identificationConfidence: 0,
            coordinate: nil,
            distanceMetres: 400,
            discoveredAt: epoch,
            registeredOnDay: 0
        ))
        #expect(isMet(.firstFlower, unidentified), "a photograph is forage either way")
        #expect(!isMet(.placedToFamily, unidentified), "nothing was placed anywhere")
    }

    @Test("The calendar milestone wants a photograph in all four seasons")
    func allYearRound() {
        var partial = world(patches: 3)
        for (index, day) in [0, 100, 200].enumerated() {
            partial.patches[index].registeredOnDay = day
        }
        #expect(!isMet(.gardenAllYear, partial), "winter is still empty")

        var complete = partial
        complete.patches[2].registeredOnDay = 300
        #expect(!isMet(.gardenAllYear, complete), "autumn was given away")

        complete.patches.append(complete.patches[0])
        complete.patches[3].registeredOnDay = 200
        #expect(isMet(.gardenAllYear, complete))
    }

    @Test("A shared flower is noticed by the share, not the patch")
    func sharedFlower() {
        var shared = world(patches: 1)
        #expect(!isMet(.firstSharedFlower, shared))
        shared.importedShares.insert("someone-else-clover")
        #expect(isMet(.firstSharedFlower, shared))
    }

    @Test("Population milestones are thresholds on the adults")
    func population() {
        var big = world()
        var ids = IDGenerator()
        // The founding colony has 25 adults; take it to 250 exactly.
        while big.hive.adultCount < 250 {
            big.hive.bees.append(Bee(id: ids.next(), kind: .worker, stage: .adult, daysInStage: 10))
        }

        #expect(isMet(.hundredAdults, big))
        #expect(isMet(.twoHundredAdults, big))
        #expect(!isMet(.fiveHundredAdults, big))
        #expect(!isMet(.hundredAdults, world()), "a founding colony is 25 bees")
    }

    @Test("Honey taken and the entrance sealed are read from the world")
    func playerActionsThatLeaveState() {
        var world = world()
        #expect(!isMet(.firstHoney, world))
        #expect(!isMet(.sealedForWinter, world))

        world.honeyTaken = 12
        world.entranceSealed = true
        #expect(isMet(.firstHoney, world))
        #expect(isMet(.sealedForWinter, world))
    }

    @Test("Naming a queen is read from the lineage")
    func namedQueen() {
        var world = world()
        world.lineage.found(onDay: 0, patrilines: 12)
        #expect(!isMet(.queenNamed, world))
        world.lineage.name(1, "Boudica")
        #expect(isMet(.queenNamed, world))
    }

    /// The one condition that needs both a past event and a present state.
    @Test("A supersedure only counts once the successor is laying")
    func supersedure() {
        var world = world()
        world.lineage.found(onDay: 0, patrilines: 12)
        world.lineage.crown(onDay: 300, quality: 0.9)
        world.lineage.endQueen(number: 1, onDay: 300, .superseded)

        world.hive.queenIsMated = false
        #expect(!isMet(.supersedureSurvived, world), "the daughter has not flown yet")

        world.hive.queenIsMated = true
        #expect(isMet(.supersedureSurvived, world))

        // A queen lost rather than superseded is a different story entirely.
        var lost = self.world()
        lost.lineage.found(onDay: 0, patrilines: 12)
        lost.lineage.end(onDay: 40, .lost)
        lost.hive.queenIsMated = true
        #expect(!isMet(.supersedureSurvived, lost))
    }

    @Test("Winter is survived by being alive on the first day of the next spring")
    func winters() {
        let alive = world()
        #expect(!isMet(.firstWinterSurvived, alive, day: Season.daysPerYear - 1))
        #expect(isMet(.firstWinterSurvived, alive, day: Season.daysPerYear))
        #expect(!isMet(.secondWinterSurvived, alive, day: Season.daysPerYear))
        #expect(isMet(.secondWinterSurvived, alive, day: 2 * Season.daysPerYear))

        var gone = world()
        gone.hive.bees = []
        #expect(gone.hive.isCollapsed)
        #expect(!isMet(.firstWinterSurvived, gone, day: Season.daysPerYear),
                "an empty nest did not get through anything")
    }

    @Test("Raids driven off are counted across the colony's whole life")
    func raidsRepelled() {
        var world = world()
        #expect(!isMet(.firstRaidRepelled, world))
        #expect(isMet(.firstRaidRepelled, world, events: [.attackRepelled(.wasp)]))

        // The almanac's tallies are the count that survives a save; this
        // tick's events are added to them because the almanac is written after
        // the pipeline has run.
        world.almanac.chronicle(
            Array(repeating: .attackRepelled(.wasp), count: 9),
            day: 100, honey: 40, lineage: world.lineage
        )
        #expect(isMet(.firstRaidRepelled, world))
        #expect(!isMet(.tenRaidsRepelled, world))
        #expect(isMet(.tenRaidsRepelled, world, events: [.attackRepelled(.hornet)]))
    }

    // MARK: - Conditions read from the tick's events

    @Test("The momentary milestones are read from this tick's events")
    func eventConditions() {
        let world = world()

        #expect(!isMet(.firstComb, world))
        #expect(isMet(.firstComb, world, events: [.cellsBuilt(count: 8, type: .worker)]))

        #expect(!isMet(.firstBrood, world))
        #expect(isMet(.firstBrood, world, events: [.emerged(.worker)]))

        #expect(!isMet(.firstQueenMated, world))
        #expect(isMet(.firstQueenMated, world, events: [.queenMated(patrilines: 14)]))

        #expect(!isMet(.firstSwarm, world))
        #expect(isMet(.firstSwarm, world, events: [.swarmed(beesLost: 200)]))

        #expect(!isMet(.swarmTalkedOut, world))
        #expect(isMet(.swarmTalkedOut, world, events: [.swarmAbandoned]))

        #expect(!isMet(.firstSplit, world))
        #expect(isMet(.firstSplit, world, events: [.colonyDivided(beesLeft: 60)]))

        // A swarm is not a split and a split is not a swarm.
        #expect(!isMet(.firstSplit, world, events: [.swarmed(beesLost: 200)]))
        #expect(!isMet(.firstSwarm, world, events: [.colonyDivided(beesLeft: 60)]))
    }

    // MARK: - Awarded exactly once

    @Test("A milestone is awarded once and never again")
    func awardedOnce() {
        var world = world(patches: 1)

        let first = run(&world, day: 5)
        #expect(first.contains(.milestone(.firstFlower)))
        #expect(world.milestones.day(of: .firstFlower) == 5)

        // The condition is still true, and stays true for the rest of the
        // colony's life. It must not speak again.
        let second = run(&world, day: 6)
        #expect(!second.contains(.milestone(.firstFlower)))
        #expect(world.milestones.day(of: .firstFlower) == 5)

        let third = run(&world, day: 400)
        #expect(third.isEmpty == false, "day 400 is past the first winter")
        #expect(third.contains(.milestone(.firstWinterSurvived)))
        #expect(!third.contains(.milestone(.firstFlower)))
        #expect(world.milestones.achieved.filter { $0.milestone == .firstFlower }.count == 1)
    }

    @Test("A momentary event that recurs is only a first once")
    func repeatedEvent() {
        var world = world()

        let first = run(&world, events: [.swarmed(beesLost: 200)], day: 140)
        #expect(first.contains(.milestone(.firstSwarm)))

        let again = run(&world, events: [.swarmed(beesLost: 180)], day: 500)
        #expect(!again.contains(.milestone(.firstSwarm)))
        #expect(world.milestones.day(of: .firstSwarm) == 140)
    }

    @Test("Several firsts on the same day are all awarded")
    func severalAtOnce() {
        var world = world(patches: 12)
        let awarded = run(&world, events: [.emerged(.worker)], day: 30)

        #expect(awarded.contains(.milestone(.firstFlower)))
        #expect(awarded.contains(.milestone(.tenFlowers)))
        #expect(awarded.contains(.milestone(.fiveFamilies)))
        #expect(awarded.contains(.milestone(.firstBrood)))
        #expect(world.milestones.count == awarded.count)
        // Declaration order, so the badge page reads in a sensible order
        // whatever order the conditions happened to become true in.
        #expect(world.milestones.achieved.first?.milestone == .firstFlower)
    }

    // MARK: - Through the simulation

    @Test("A played colony earns its garden badges and reports them")
    func throughTheSimulation() {
        var simulation = Fixture.thrivingSimulation(patches: 12, seed: 8_919)
        #expect(simulation.milestones.isEmpty)

        let report = simulation.runDays(3)

        #expect(simulation.milestones.has(.firstFlower))
        #expect(simulation.milestones.has(.tenFlowers))
        #expect(simulation.milestones.day(of: .firstFlower) == 0)

        // The report carries them twice over: in the highlight timeline the
        // catch-up screen reads, and in a list of its own that the cap on
        // highlights cannot throw away.
        #expect(report.highlights.contains(.milestone(.firstFlower)))
        #expect(report.milestones.contains(.firstFlower))

        // And the almanac has a line for it.
        #expect(simulation.world.almanac.entries.contains {
            $0.text.lowercased().contains(Milestone.firstFlower.title.lowercased())
        })
    }

    /// The whole point of putting the system last and giving it nothing to do
    /// but read. `DeterminismTests` is the model for this.
    @Test("Milestones change nothing about how the colony runs")
    func determinism() {
        var a = Fixture.thrivingSimulation(patches: 12, seed: 99)
        var b = Fixture.thrivingSimulation(patches: 12, seed: 99)

        a.runDays(40)
        b.runDays(40)

        #expect(a == b, "identical seeds diverged")
        #expect(!a.milestones.isEmpty, "no milestone was earned, so this proved nothing")
    }

    /// The narrower and stronger version of the claim above: on a tick where
    /// the system awards a whole handful of badges, the only thing it changed
    /// was the record, and it drew nothing from the random stream.
    @Test("The system draws no randomness and touches nothing but the record")
    func readsOnly() {
        var world = world(patches: 12)
        world.lineage.found(onDay: 0, patrilines: 12)
        world.honeyTaken = 8
        let before = world

        var context = TickContext(
            clock: SimClock(epoch: epoch, tick: 30 * SimClock.ticksPerDay),
            config: .standard,
            rng: SeededRandom(seed: 0x5EED_B335),
            ids: IDGenerator(startingAt: 5_000)
        )
        let rngBefore = context.rng
        let idsBefore = context.ids

        MilestoneSystem().update(&world, &context)

        #expect(!world.milestones.isEmpty, "nothing was awarded, so this proved nothing")
        #expect(context.rng == rngBefore, "a badge cost the colony a random draw")
        #expect(context.ids == idsBefore, "a badge consumed an entity identifier")

        // Everything except the record, compared by putting the old record
        // back: if that makes the two worlds equal, nothing else moved.
        var after = world
        after.milestones = before.milestones
        #expect(after == before, "the system changed something other than the record")
    }

    @Test("Milestones survive a save and are not earned twice on reload")
    func acrossASave() throws {
        var simulation = Fixture.thrivingSimulation(patches: 12, seed: 21)
        simulation.runDays(5)
        let earned = simulation.milestones.count
        #expect(earned > 0)

        let data = try JSONEncoder().encode(simulation)
        var restored = try JSONDecoder().decode(Simulation.self, from: data)
        #expect(restored.milestones == simulation.milestones)

        let report = restored.runDays(1)
        #expect(!report.milestones.contains(.firstFlower),
                "the garden badges were handed out a second time after a reload")
    }
}
