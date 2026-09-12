//
//  MilestoneSystem.swift
//  FlowerPowerCore
//
//  Notices what the colony just did for the first time.
//
//  Last in the pipeline, after `LineageSystem`, for the same reason that one
//  is last: it reads the finished world and the tick's events and writes only
//  to `world.milestones`. Nothing downstream of it exists, nothing upstream
//  depends on it, and it touches neither the random stream nor the id
//  generator — so adding it cannot move the balance baseline by a single
//  colony. That property is worth more than the feature is, and
//  `MilestoneTests` asserts it directly.
//
//  It runs after the lineage because two conditions read the record the
//  lineage system has just written: a supersedure the colony came through, and
//  a queen the player has named.
//
//  Every condition here is a *state*, not a notification. Where the state is
//  durable — honey taken, the entrance sealed, a family in the garden — the
//  world is asked. Where the thing itself is momentary and leaves no trace a
//  badge could be recovered from — a swarm leaving, a queen coming home mated,
//  a wasp turned away — the tick's events are asked instead. That difference
//  decides which of the two a condition below is written against, and it is
//  the reason a colony saved before milestones existed picks most of them up
//  on its next tick rather than having to earn them again.
//

import Foundation

public struct MilestoneSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        // Read the events once, before emitting. `emit` appends to the same
        // array, and a condition that saw its own milestone events would be
        // reasoning about its own output.
        let events = context.events

        for milestone in Milestone.allCases {
            guard !world.milestones.has(milestone) else { continue }
            guard Self.isMet(milestone, world, events, day: context.day) else { continue }

            // `award` is what makes "once, ever" true; the event follows from
            // it rather than from the condition, so a condition that stays
            // true for the next two years still only speaks once.
            if world.milestones.award(milestone, onDay: context.day) {
                context.emit(.milestone(milestone))
            }
        }
    }

    // MARK: - The conditions

    /// Whether this milestone has just become true.
    ///
    /// `static` and taking the world by value: a condition that could mutate
    /// the world would be a system in disguise, and this one is not allowed to
    /// change anything but the record.
    static func isMet(
        _ milestone: Milestone,
        _ world: World,
        _ events: [SimEvent],
        day: Int
    ) -> Bool {
        switch milestone {

        // MARK: The garden
        //
        // Counted from the patches rather than from a registration event,
        // because a photograph is registered by a player action between ticks
        // and there is no event for it. The garden is the state.

        case .firstFlower:
            return !world.patches.isEmpty
        case .tenFlowers:
            return world.patches.count >= 10
        case .placedToFamily:
            // Any identification at all places the plant in a family: the
            // classifier reports to whatever rank it can reach, and a family
            // is the coarsest of them. See `Taxon.rank`.
            return world.patches.contains { $0.species != nil }
        case .fiveFamilies:
            return familiesInGarden(world).count >= 5
        case .tenFamilies:
            return familiesInGarden(world).count >= 10
        case .gardenAllYear:
            return seasonsPhotographed(world).count == Season.allCases.count
        case .firstSharedFlower:
            return !world.importedShares.isEmpty

        // MARK: The nest

        case .firstComb:
            // The event, not `comb.builtCells`: a founding colony arrives with
            // comb already drawn, so the count is never zero and the bees
            // drawing their own first cells would never be noticed.
            return events.contains { if case .cellsBuilt = $0 { true } else { false } }
        case .firstBrood:
            return events.contains { if case .emerged = $0 { true } else { false } }
        case .hundredAdults:
            return world.hive.adultCount >= 100
        case .twoHundredAdults:
            return world.hive.adultCount >= 200
        case .fiveHundredAdults:
            return world.hive.adultCount >= 500

        // MARK: The queens

        case .firstQueenMated:
            // The founding queen is recorded as mated on day zero because she
            // arrived with the swarm that way, so the lineage cannot tell a
            // mating flight from a founding. The event can.
            return events.contains { if case .queenMated = $0 { true } else { false } }
        case .supersedureSurvived:
            // State, because "came through it" is only knowable later: the
            // mother has to have been superseded *and* her successor has to be
            // laying. On the day of the supersedure the daughter is usually a
            // virgin who has not flown yet.
            return world.lineage.queens.contains { $0.ending == .superseded }
                && world.hive.hasLayingQueen
        case .queenNamed:
            return world.lineage.queens.contains { $0.name != nil }

        // MARK: Dividing

        case .firstSwarm:
            return events.contains { if case .swarmed = $0 { true } else { false } }
        case .swarmTalkedOut:
            return events.contains(.swarmAbandoned)
        case .firstSplit:
            return events.contains { if case .colonyDivided = $0 { true } else { false } }

        // MARK: Stores and the winter

        case .firstHoney:
            return world.honeyTaken > 0
        case .sealedForWinter:
            return world.entranceSealed
        case .firstWinterSurvived:
            return day >= Season.daysPerYear && !world.hive.isCollapsed
        case .secondWinterSurvived:
            return day >= 2 * Season.daysPerYear && !world.hive.isCollapsed

        // MARK: The entrance

        case .firstRaidRepelled:
            return repelsSoFar(world, events) >= 1
        case .tenRaidsRepelled:
            return repelsSoFar(world, events) >= 10
        }
    }

    // MARK: - Reading the world

    /// The plant families the garden holds, however coarsely identified.
    ///
    /// Derived the same way `BotanyCollection` derives it, so the badge and
    /// the garden page can never disagree about how many families there are.
    private static func familiesInGarden(_ world: World) -> Set<PlantFamily> {
        Set(world.patches.compactMap { $0.species?.taxon.family })
    }

    /// The simulated seasons in which the player has registered a flower.
    ///
    /// `registeredOnDay` rather than the photograph's own date: the milestone
    /// is about the colony's year, and a patch carried over from a previous
    /// colony is re-registered on the new one's clock — see
    /// `Simulation.newGame(at:startingAt:inheriting:)`.
    private static func seasonsPhotographed(_ world: World) -> Set<Season> {
        Set(world.patches.compactMap(\.registeredOnDay).map(Season.init(day:)))
    }

    /// Raids driven off over the colony's whole life, including this tick's.
    ///
    /// The almanac's tallies are the only running count of this that survives
    /// a save — `world.attackHistory` is trimmed to the last forty — and they
    /// are written *after* the pipeline, so this tick's repels are not in them
    /// yet and have to be added by hand. See `Simulation.step`.
    private static func repelsSoFar(_ world: World, _ events: [SimEvent]) -> Int {
        let recorded = world.almanac.tallies.reduce(0) { $0 + $1.raidsRepelled }
        let thisTick = events.reduce(into: 0) { count, event in
            if case .attackRepelled = event { count += 1 }
        }
        return recorded + thisTick
    }
}
