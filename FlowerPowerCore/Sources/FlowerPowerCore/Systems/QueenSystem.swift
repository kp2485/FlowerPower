//
//  QueenSystem.swift
//  FlowerPowerCore
//
//  Egg laying, queen rearing, mating flights and succession.
//
//  A colony raises queen cells for three quite different reasons, and telling
//  them apart matters: swarm cells mean the colony is about to divide,
//  supersedure cells mean it is quietly replacing a failing queen, and
//  emergency cells mean it has already lost her and is gambling on brood that
//  may be too old to make a decent queen from.
//

import Foundation

public struct QueenSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        attemptMatingFlight(&world, &context)
        layEggs(&world, &context)
        considerQueenRearing(&world, &context)
        emergeQueens(&world, &context)
        checkForLayingWorkers(&world, &context)
    }

    // MARK: - Mating

    /// A virgin queen flies to a drone congregation area at around six days
    /// old, mates with a dozen or more drones in a single afternoon, and never
    /// flies again. She needs warm, calm weather in a narrow window; if she
    /// misses it she remains a virgin and the colony is finished.
    private func attemptMatingFlight(_ world: inout World, _ context: inout TickContext) {
        guard world.hive.hasVirginQueen, let queen = world.hive.queen else { return }

        let age = queen.daysInStage
        guard age >= context.config.matingFlightEarliestDay else { return }

        // Past the window her spermatheca never fills and she is finished as a
        // queen — she will lay, but only drones.
        //
        // Resolving this state matters. Leaving her an eternal virgin left the
        // colony with a queen it could neither use nor replace: no brood, so no
        // warming, so no brood. A whole overwintered colony starved that way in
        // testing, at full strength, with a queen sitting on the comb.
        if age > context.config.matingFlightLatestDay {
            world.hive.queenIsMated = true
            world.hive.genetics.patrilines = 0
            context.emit(.matingFlightFailed)
            return
        }

        guard world.weather.isFlyingWeather,
              world.weather.temperatureCelsius >= context.config.matingFlightMinimumTemperature,
              world.weather.sky == .clear || world.weather.sky == .cloudy
        else { return }

        // Predation on the flight is a real and significant risk.
        if context.rng.chance(context.config.matingFlightPredationChance) {
            removeQueen(&world, &context, cause: .predation)
            context.emit(.matingFlightFailed)
            return
        }

        // How many drones she meets depends on the day and on how many drones
        // the wider landscape is carrying.
        let seasonalDroneAvailability: Double
        switch context.season {
        case .spring, .summer: seasonalDroneAvailability = 1.0
        case .autumn: seasonalDroneAvailability = 0.45
        case .winter: seasonalDroneAvailability = 0.05
        }

        let quality = world.weather.forageFactor * seasonalDroneAvailability
        let encounters = Int(
            (context.config.baseDroneEncounters * quality * (0.6 + context.rng.unitValue() * 0.8))
                .rounded()
        )

        world.hive.genetics = QueenGenetics.fromMatingFlight(
            droneEncounters: max(0, encounters),
            maternal: world.hive.genetics,
            rng: &context.rng
        )

        if world.hive.genetics.isProperlyMated {
            world.hive.queenIsMated = true
            context.emit(.queenMated(patrilines: world.hive.genetics.patrilines))
        } else {
            // Poorly mated queens do start laying, but only drones, and the
            // colony dwindles. Treated as a failure the player can act on.
            world.hive.queenIsMated = true
            context.emit(.matingFlightFailed)
        }
    }

    // MARK: - Laying

    private func layEggs(_ world: inout World, _ context: inout TickContext) {
        guard world.hive.hasLayingQueen, let queen = world.hive.queen else {
            layWorkerEggsIfHopeless(&world, &context)
            return
        }

        let limit = layingCapacity(world, context, queen: queen)
        guard limit > 0 else { return }

        // A poorly mated queen has no viable sperm and lays only drones.
        let dronesOnly = !world.hive.genetics.isProperlyMated

        var workersLaid = 0
        var dronesLaid = 0

        let droneShare = dronesOnly ? 1.0 : droneLayingShare(world, context)

        for _ in 0..<limit {
            let layDrone = context.rng.chance(droneShare)
            let kind: BeeKind = layDrone ? .drone : .worker

            guard world.hive.layingSpace(for: kind) > (layDrone ? dronesLaid : workersLaid) else {
                continue
            }

            let patriline = UInt8(
                context.rng.next() % UInt64(max(1, world.hive.genetics.patrilines))
            )

            world.hive.bees.append(Bee(
                id: context.ids.next(),
                kind: kind,
                patriline: patriline,
                // Brood quality inherits the queen's condition.
                vitality: min(1, 0.7 + 0.3 * queen.vitality)
            ))

            if layDrone { dronesLaid += 1 } else { workersLaid += 1 }
        }

        if workersLaid > 0 { context.emit(.eggsLaid(count: workersLaid, kind: .worker)) }
        if dronesLaid > 0 { context.emit(.eggsLaid(count: dronesLaid, kind: .drone)) }
    }

    /// Everything that can throttle a queen's output.
    private func layingCapacity(_ world: World, _ context: TickContext, queen: Bee) -> Int {
        // Her intrinsic rate, declining with age and condition.
        let ageFraction = Double(queen.daysInStage)
            / Double(BeeKind.queen.baseAdultLifespanDays())
        let vigour = queen.vitality * (1 - 0.5 * min(1, ageFraction))
        let intrinsic = Double(context.config.maxEggsPerDay)
            * world.hive.genetics.fecundity
            * vigour

        // Brood rearing follows the season closely: it ramps hard in spring,
        // peaks early summer, and stops almost entirely in winter.
        let seasonal: Double
        switch context.season {
        case .spring: seasonal = 0.7 + 0.3 * Season.progress(context.day)
        // Laying peaks in early summer and eases off through the second half,
        // as the colony turns from expansion to provisioning.
        case .summer: seasonal = 1.0 - 0.45 * max(0, Season.progress(context.day) - 0.4) / 0.6
        // Autumn brood rearing winds down hard. The colony is not building a
        // workforce any more — it is rearing the specific cohort of winter bees
        // that has to survive until spring, and then stopping. A gentle taper
        // leaves it carrying a summer-sized population into a season with
        // nothing coming in.
        case .autumn: seasonal = max(0.02, 0.45 * pow(1 - Season.progress(context.day), 2))
        // Brood rearing restarts in late winter, weeks before there is
        // anything to forage. It has to: the winter bees are dying of old age
        // and their replacements take three weeks from egg to emergence, so a
        // colony that waits for spring has already lost the race. Every test
        // colony that overwintered in good order then died in March did so for
        // exactly this reason.
        case .winter:
            let progress = Season.progress(context.day)
            seasonal = progress < context.config.winterBuildUpStart
                ? 0.02
                : 0.02 + 0.6 * (progress - context.config.winterBuildUpStart)
                    / max(0.01, 1 - context.config.winterBuildUpStart)
        }

        // She can only lay as fast as nurses can feed the result.
        let nurses = world.hive.workforce(for: .nurseBee)
        let nurseLimit = nurses / context.config.nursesPerEgg

        // And only into cells that exist and are empty.
        let spaceLimit = Double(world.hive.layingSpace(for: .worker) + world.hive.layingSpace(for: .drone))

        // Brood cannot be reared in a cold nest.
        let warmEnough = world.hive.temperatureCelsius >= context.config.minimumBroodTemperature
        guard warmEnough else { return 0 }

        // Nor without food coming in or banked.
        guard world.hive.resources.edibleEnergy >= context.config.layingEnergyThreshold else {
            return 0
        }

        // Brood rearing follows the flow. A colony will not rear more brood
        // than it can actually feed — it reads the incoming nectar and its own
        // reserves and lays to match. Without this the queen cheerfully lays a
        // nest full of larvae that all starve, taking the colony with them.
        let foodLimit = broodHeadroom(world, context)

        let capacity = min(min(intrinsic * seasonal, nurseLimit), min(spaceLimit, foodLimit))
        return max(0, Int(capacity))
    }

    /// How many *more* larvae the colony's food supply can carry, expressed as
    /// eggs it is safe to lay today.
    private func broodHeadroom(_ world: World, _ context: TickContext) -> Double {
        let dailyCostPerLarva = context.config.foodPerLarva * Double(SimClock.ticksPerDay)
        guard dailyCostPerLarva > 0 else { return 0 }

        // What is coming in, converted to honey equivalent.
        let dailyIncome = world.averageNectarIntake / context.config.nectarPerHoney

        // Plus a measured draw on the reserve above the laying threshold. The
        // colony is willing to spend savings on brood, but not all of them —
        // and from autumn onward it will not touch what it needs for winter.
        // A colony that rears brood on its winter stores dies in February.
        let floor: Double
        switch context.season {
        case .autumn:
            floor = max(
                context.config.layingEnergyThreshold,
                world.hive.winterStoresRequired * Season.progress(context.day)
            )
        case .winter:
            floor = max(
                context.config.layingEnergyThreshold,
                world.hive.winterStoresRequired * (1 - Season.progress(context.day))
            )
        case .spring, .summer:
            floor = context.config.layingEnergyThreshold
        }

        let spendableReserve = max(0, world.hive.resources.edibleEnergy - floor)
        let reserveDraw = spendableReserve * context.config.broodReserveDrawRate

        // Feeding a larva costs more than the raw food: royal jelly and bee
        // bread are both made from honey and pollen with losses along the way.
        let supportable = (dailyIncome + reserveDraw)
            / (dailyCostPerLarva * context.config.broodFoodOverhead)

        // Food in the pantry is not food in a larva. Royal jelly is secreted
        // from a nurse's glands, so the nursing workforce is a hard ceiling on
        // brood regardless of how full the stores are.
        let nurseCapacity = world.hive.workforce(for: .nurseBee) * context.config.broodPerNurse

        // Only open brood counts against that ceiling. Eggs are not yet
        // feeding and sealed pupae have already been fed and capped — neither
        // costs a nurse anything.
        //
        // Counting all brood here throttled the colony to a standstill: laying
        // filled the nursing budget within three days, and since nothing
        // emerged for another seventeen, the queen simply stopped. Colonies
        // plateaued at a few dozen bees and never recovered.
        let mouths = Double(world.hive.openBroodCount)

        var headroom = max(0, min(supportable, nurseCapacity) - mouths)

        // In autumn there is one more limit, and it is the one that decides
        // whether the colony sees spring: do not rear more winter bees than the
        // stores can carry through the dearth.
        //
        // A colony that keeps rearing on summer's momentum goes into November
        // with a magnificent cluster and nowhere near enough honey to feed it.
        // Real colonies read their own stores and size the winter cohort to
        // match, which is why a well-provisioned hive overwinters strong and a
        // light one overwinters small rather than dying.
        if Season.isRearingWinterBees(on: context.day) {
            headroom = min(headroom, winterCohortHeadroom(world, context))
        }

        return headroom
    }

    /// How many more bees the colony can afford to add to its winter cluster.
    private func winterCohortHeadroom(_ world: World, _ context: TickContext) -> Double {
        let insulationPenalty = 1.0 + (1.0 - world.hive.location.type.insulation)
        let thrift = 1.0 - 0.25 * world.hive.genetics.thriftiness
        let costPerBee = Hive.winterHoneyPerBee
            * insulationPenalty
            * thrift
            * context.config.winterProvisioningMargin
        guard costPerBee > 0 else { return .infinity }

        // What is banked now, plus a modest expectation of the autumn flow
        // still to come.
        // Days left before the dearth proper begins, counting from wherever in
        // late summer or autumn we currently are.
        let remainingForageDays: Double
        switch context.season {
        case .summer:
            remainingForageDays = Double(Season.daysPerSeason)
                * (1 - Season.progress(context.day))
                + Double(Season.daysPerSeason)
        case .autumn:
            remainingForageDays = Double(Season.daysPerSeason)
                * (1 - Season.progress(context.day))
        default:
            remainingForageDays = 0
        }
        let remainingAutumn = remainingForageDays

        // Recent intake still reflects the summer flow at the start of autumn,
        // and the flow is about to fall away. Discount for the season fading as
        // well as for the colony's general caution — a colony that sizes its
        // cluster on midsummer income rears bees it cannot feed by February.
        let seasonalDecay = 1 - Season.progress(context.day)
        let expectedIncome = world.averageNectarIntake
            / context.config.nectarPerHoney
            * remainingAutumn
            * seasonalDecay
            * context.config.autumnIncomeOptimism

        // The stores have to get the colony through the rest of autumn *before*
        // they feed anybody through winter. A large summer workforce eats a
        // remarkable amount on its way out — enough that a colony sizing its
        // cluster on today's stores alone consistently reared roughly twice the
        // bees it could actually carry to spring.
        let averagePopulation = Double(world.hive.adultCount) * 0.5
        let autumnBurn = averagePopulation
            * context.config.honeyPerAdult
            * Double(SimClock.ticksPerDay)
            * remainingAutumn

        let available = world.hive.resources.edibleEnergy + expectedIncome - autumnBurn
        let affordableCluster = max(0, available) / costPerBee

        // Only bees that will actually still be there in spring count.
        //
        // Counting every winter bee currently alive badly overstates the
        // cluster: a bee reared in August is a winter bee, but she dies in
        // February, well before the colony needs her. Colonies were therefore
        // declaring themselves full in early autumn, stopping laying for four
        // months, and then losing the whole cohort at once — every bee having
        // been reared in the same narrow window and aging out in the same week.
        //
        // Judging by who will still be alive keeps the colony topping up
        // through autumn and gives the cluster a staggered age structure.
        let horizon = Double(Season.daysUntilSpring(from: context.day))

        let alreadyCommitted = world.hive.bees.filter { bee in
            if bee.isBrood { return true }
            guard bee.isAdult, bee.kind == .worker, bee.physiology == .winter else { return false }
            let remainingLife = bee.effectiveLifespanDays - Double(bee.daysInStage) - bee.wear
            return remainingLife > horizon
        }.count

        return max(0, affordableCluster - Double(alreadyCommitted))
    }

    /// Drone rearing peaks in late spring, when the colony is preparing for
    /// swarm season and mating flights.
    private func droneLayingShare(_ world: World, _ context: TickContext) -> Double {
        guard world.hive.comb[.drone] > 0 else { return 0 }

        switch context.season {
        case .spring, .summer:
            // Only a colony with resources to spare rears drones.
            guard world.hive.adultWorkerCount > context.config.droneRearingMinimumPopulation else {
                return 0
            }
            return context.config.droneEggShare
        case .autumn, .winter:
            return 0
        }
    }

    // MARK: - Queen rearing

    private func considerQueenRearing(_ world: inout World, _ context: inout TickContext) {
        // One decision at a time; a colony committed to a course sticks with it.
        guard world.hive.comb.queenCells.count < context.config.maximumQueenCells else { return }

        if let purpose = queenRearingPurpose(world, &context) {
            // Emergency queens come from larvae already too old for the job.
            let quality: Double
            switch purpose {
            case .swarm: quality = 1.0
            case .supersedure: quality = 0.95
            case .emergency: quality = 0.6 + context.rng.unitValue() * 0.2
            }

            // Building a queen cell costs wax — and if the colony has none
            // banked it will render some from honey there and then.
            //
            // The fallback is load-bearing. `ConstructionSystem` spends wax the
            // moment it is made, so a busy colony sits at zero wax almost
            // permanently. Without this, a colony that lost its queen could not
            // afford the one cell that would save it, and died with a full
            // larder and a nest of perfectly good young brood.
            // A queenless colony starts several cells at once; a colony calmly
            // superseding or preparing to swarm builds them one at a time.
            let wanted = purpose == .emergency ? context.config.emergencyQueenCellBurst : 1
            let room = context.config.maximumQueenCells - world.hive.comb.queenCells.count

            var started = 0
            for _ in 0..<min(wanted, room) {
                guard affordQueenCell(&world, &context) else { break }
                world.hive.comb.addQueenCell(QueenCell(
                    id: context.ids.next(),
                    purpose: purpose,
                    quality: quality
                ))
                started += 1
            }

            guard started > 0 else { return }
            context.emit(.queenCellStarted(purpose))
        }
    }

    /// Pays for one queen cell, secreting wax from honey if the store is empty.
    private func affordQueenCell(_ world: inout World, _ context: inout TickContext) -> Bool {
        let cost = CellType.queenCup.waxCost

        if world.hive.resources.consume(cost, of: .wax) { return true }

        let shortfall = cost - world.hive.resources[.wax]
        let honeyNeeded = shortfall * context.config.honeyPerWax
        guard world.hive.resources[.honey] >= honeyNeeded else { return false }

        world.hive.resources.drain(honeyNeeded, of: .honey)
        world.hive.resources.add(shortfall, of: .wax)
        return world.hive.resources.consume(cost, of: .wax)
    }

    private func queenRearingPurpose(
        _ world: World,
        _ context: inout TickContext
    ) -> QueenCell.Purpose? {
        let qmp = world.hive.pheromones.queenMandibular

        // Queenless: raise an emergency queen from whatever young brood remains.
        if !world.hive.isQueenright {
            guard world.hive.canStillRearAQueen else { return nil }
            return .emergency
        }

        guard let queen = world.hive.queen else { return nil }

        // Failing queen: poor condition or old age triggers a quiet replacement.
        let ageFraction = Double(queen.daysInStage)
            / Double(BeeKind.queen.baseAdultLifespanDays())
        let isFailing = queen.vitality < context.config.queenFailureVitality
            || ageFraction > context.config.queenSupersedureAge
            || !world.hive.genetics.isProperlyMated

        // Requeening is only worth attempting when there are drones flying to
        // mate the replacement. A colony that supersedes in autumn destroys
        // itself: the new queen emerges into a landscape with no drones and no
        // mating weather, stays a virgin, and the colony dies broodless in
        // spring. Real colonies supersede in spring and early summer.
        let replacementCanMate = context.season == .spring || context.season == .summer

        if isFailing, replacementCanMate, context.rng.chance(context.config.supersedureChance) {
            return .supersedure
        }

        // Swarm preparation: a crowded colony in a flow, with the queen's
        // signal too dilute to suppress it.
        let season = context.season
        // Swarming tracks the spring flow. A colony that divides in late summer
        // has neither the workforce nor the season left to provision two nests,
        // and both halves go into winter short — which is exactly what happened
        // when any summer day would do: swarming roughly tripled second-year
        // starvation deaths.
        let isSwarmSeason = season == .spring
            || (season == .summer && Season.progress(context.day) < Season.swarmSeasonEndsAtSummerProgress)
        let crowded = world.hive.swarmPressure >= context.config.swarmCongestionThreshold
        let signalWeak = qmp < Pheromones.queenRearingThreshold
        let strongEnough = world.hive.adultWorkerCount >= context.config.swarmMinimumPopulation

        if isSwarmSeason, crowded, signalWeak, strongEnough, world.isInFlow {
            let urge = context.config.swarmCellChance * (0.5 + world.hive.genetics.swarminess)
            if context.rng.chance(urge) {
                return .swarm
            }
        }

        return nil
    }

    // MARK: - Emergence and succession

    private func emergeQueens(_ world: inout World, _ context: inout TickContext) {
        guard let ready = world.hive.comb.readyQueenCells.first else { return }

        // Swarm cells are consumed by SwarmSystem, which needs the old queen to
        // leave first. If the colony is still queenright and this is a swarm
        // cell, wait.
        if ready.purpose == .swarm && world.hive.isQueenright { return }

        // The emerging virgin destroys her rivals — but only the ones ready to
        // emerge. Cells still developing are left standing as insurance.
        //
        // This matters more than it looks. A virgin queen has to survive a
        // mating flight, and when she does not, a colony that tore down every
        // cell has nothing left and dies queenless. Keeping the immature cells
        // gives it the second attempt real colonies get.
        world.hive.comb.queenCells.removeAll(where: \.isReady)

        // The old queen, if any, is killed by the newcomer.
        if world.hive.isQueenright {
            removeQueen(&world, &context, cause: .oldAge)
            context.emit(.supersededQueen)
        }

        world.hive.bees.append(Bee(
            id: context.ids.next(),
            kind: .queen,
            stage: .adult,
            daysInStage: 0,
            vitality: ready.quality
        ))
        world.hive.queenIsMated = false
        world.hive.daysQueenless = 0

        context.emit(.queenEmerged(quality: ready.quality))
    }

    /// A colony queenless too long, with no brood left to rear a queen from,
    /// develops laying workers. Their unfertilised eggs produce only drones and
    /// the colony is finished — it just takes a few weeks to admit it.
    private func checkForLayingWorkers(_ world: inout World, _ context: inout TickContext) {
        guard !world.hive.hasLayingWorkers,
              !world.hive.isQueenright,
              !world.hive.canStillRearAQueen,
              world.hive.comb.queenCells.isEmpty,
              world.hive.daysQueenless >= context.config.layingWorkerOnsetDays
        else { return }

        world.hive.hasLayingWorkers = true
        context.emit(.layingWorkersAppeared)
    }

    private func layWorkerEggsIfHopeless(_ world: inout World, _ context: inout TickContext) {
        guard world.hive.hasLayingWorkers else { return }

        // Laying workers are prolific but produce nothing but drones.
        let count = min(
            context.config.layingWorkerEggsPerDay,
            world.hive.layingSpace(for: .drone)
        )
        guard count > 0 else { return }

        for _ in 0..<count {
            world.hive.bees.append(Bee(
                id: context.ids.next(),
                kind: .drone,
                vitality: 0.7
            ))
        }
        context.emit(.eggsLaid(count: count, kind: .drone))
    }

    private func removeQueen(
        _ world: inout World,
        _ context: inout TickContext,
        cause: DeathCause
    ) {
        guard let index = world.hive.bees.firstIndex(where: {
            $0.kind == .queen && $0.isAdult
        }) else { return }

        context.emit(.died(.queen, cause))
        world.hive.bees.remove(at: index)
    }
}
