//
//  ForagingSystem.swift
//  FlowerPowerCore
//
//  A colony has no forager-in-chief. Scouts return from a patch and dance in
//  proportion to how good it was; other bees follow the most vigorous dances.
//  The result is a distributed optimiser that keeps reallocating the workforce
//  toward the best available forage — and it falls out of simply weighting
//  recruitment by patch quality, which is what this system does.
//

import Foundation

public struct ForagingSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        // Close out yesterday's tally before today's foraging starts.
        if context.isDayBoundary {
            world.rollOverNectarIntake()
        }

        guard context.isDaylight else { return }

        let weatherFactor = world.weather.forageFactor
        guard weatherFactor > 0 else { return }

        gatherWater(&world, &context, weatherFactor: weatherFactor)
        gatherFromPatches(&world, &context, weatherFactor: weatherFactor)
    }

    // MARK: - Water

    private func gatherWater(
        _ world: inout World,
        _ context: inout TickContext,
        weatherFactor: Double
    ) {
        let carriers = world.hive.workforce(for: .waterCarrier)
        guard carriers > 0 else { return }

        // Water is only collected when it is actually needed — to cool the nest
        // or to dilute honey for feeding brood. Bees do not hoard it, and the
        // storage cap here is what stops an unbounded lake accumulating.
        let cooling = max(0, world.hive.temperatureCelsius - context.config.targetTemperature)
        let broodDemand = Double(world.hive.openBroodCount) * 0.02
        let demand = cooling * 2.0 + broodDemand

        guard demand > 0 else { return }

        let gathered = min(
            carriers * context.config.waterPerCarrier * weatherFactor,
            demand
        )

        world.hive.resources.add(
            gathered,
            of: .water,
            limit: ResourceKind.water.uncappedStorageLimit
        )
    }

    // MARK: - Nectar and pollen

    private func gatherFromPatches(
        _ world: inout World,
        _ context: inout TickContext,
        weatherFactor: Double
    ) {
        let season = context.season
        // The colony's posture is paid for in foraging. Holding the entrance
        // means fewer bees out; a narrowed entrance is slower to fly through.
        var foragerForce = world.hive.workforce(for: .foragingBee)
            * world.posture.forageMultiplier
            // And an alarmed colony forages less whether or not the player
            // said anything. The bees are at the entrance and in the air
            // around it rather than in the field, for the few hours the signal
            // lasts.
            * (1 - world.hive.pheromones.alarm * context.config.alarmForageCost)
        // A narrowed entrance slows traffic a little. Late autumn foraging is
        // light anyway, which is why instinct waits until then to seal it.
        if world.entranceSealed { foragerForce *= 0.95 }

        // Bees looking at the country are not working it. This is the whole
        // cost of both ways of finding ground: a scouting party the player
        // sent, and the handful that wander off on their own in a dearth.
        // Multiplicative rather than additive, because a colony that is doing
        // both is not doing sixteen per cent less of nothing.
        if world.scoutingParty != nil { foragerForce *= max(0, 1 - context.config.scoutShare) }
        if world.exploringToday { foragerForce *= max(0, 1 - context.config.explorationShare) }

        guard foragerForce > 0 else { return }

        // Only patches in bloom, in range, and not stripped are worth dancing for.
        let candidates = world.patches.indices.filter { index in
            let patch = world.patches[index]
            return patch.isInBloom(during: season)
                && patch.isWithinRange
                && !patch.isDepleted
                && patch.forageQuality(onDay: context.day, config: context.config) > 0
        }
        guard !candidates.isEmpty else { return }

        // Recruitment is superlinear in quality: a patch twice as good attracts
        // far more than twice the dancers. This is what makes the colony
        // converge on the best forage rather than spreading itself evenly.
        let qualities = candidates.map { index in
            world.patches[index].forageQuality(onDay: context.day, config: context.config)
        }
        let weights = qualities.map { pow($0, context.config.danceRecruitmentExponent) }

        // The colony is served in the order the dancers rank the ground.
        //
        // Comb space runs out before the day does in a honey-bound colony, and
        // whoever is reached first gets it. Handing it out in the order patches
        // happen to sit in `world.patches` meant the oldest photograph was
        // served before the best flower — harmless while every patch was a
        // photograph registered in the order it was taken, and a visible bias
        // the moment the world starts inserting wild patches around the garden.
        // The dance is a ranking; this is what the ranking means.
        //
        // The tie-break is the patch's id, so two equally good patches are
        // always served in the same order — a sort that is not stable would
        // otherwise let the platform's sorting algorithm decide the balance.
        let ranked = candidates.indices.sorted { left, right in
            qualities[left] == qualities[right]
                ? world.patches[candidates[left]].id < world.patches[candidates[right]].id
                : qualities[left] > qualities[right]
        }

        // And the floor only holds so many. See `danceFloorPatches` — this is
        // what stops a colony that knows a whole county from splitting its
        // force two hundred and sixty ways and starving in a year of plenty.
        let floor = ranked.prefix(max(1, context.config.danceFloorPatches))

        // Summed in patch order rather than in ranking order, so a colony whose
        // floor is not full computes bit-for-bit the shares it always did and
        // the world-off balance is untouched.
        let onTheFloor = Set(floor)
        var totalWeight = 0.0
        for slot in candidates.indices where onTheFloor.contains(slot) {
            totalWeight += weights[slot]
        }
        guard totalWeight > 0 else { return }

        // Comb space limits how much unripened nectar the colony can accept. A
        // "honey bound" colony physically cannot take more in, which is one of
        // the real triggers for swarming.
        //
        // Nectar goes in less the brood nest, which is not storage: see
        // `QueenSystem.broodNestRoom`. Taking every free cell here is what let
        // a honey-bound colony with a laying queen dwindle to nothing on a
        // full larder rather than rear its way out.
        //
        // Pollen does not. It is packed in a band around the brood, where the
        // nurses who eat it are, and holding the nest against it starved the
        // brood the nest was being held for: seed 8919 under gentle, with the
        // nest kept and pollen kept out of it, ran its pollen to nothing on
        // day 432 and again from 455 to 472, and 417 of its bees died of
        // starvation over two years. Pollen collection is small and
        // demand-limited anyway, just below.
        let broodNest = QueenSystem.broodNestRoom(
            in: world.hive,
            config: context.config,
            day: context.day
        )
        let freeCells = Double(world.hive.freeCells)
        let storageCells = Double(max(0, world.hive.freeCells - broodNest))
        var nectarSpace = max(0, storageCells * ResourceKind.nectar.unitsPerCell)
        var pollenSpace = max(0, freeCells * ResourceKind.pollen.unitsPerCell)

        // Pollen collection is demand-driven in a way nectar is not. Nectar
        // becomes honey, which keeps forever and is the colony's savings, so
        // more is always welcome. Pollen is perishable protein for brood, and a
        // colony with its bread bins full simply switches its foragers over to
        // nectar. Without this the nest fills with pollen it will never eat,
        // crowding out the very brood the pollen was for.
        let pollenAppetite = pollenDemandFactor(world, context)

        let seasonFactor = context.config.forageMultiplier(in: season)
        var totalNectarGathered = 0.0
        var totalPollenGathered = 0.0
        var flightCost = 0.0

        // Foragers still looking for somewhere to go, and the dance floor they
        // are choosing from. Both shrink as patches take their share.
        //
        // **What a patch cannot serve, the next dance gets.** A patch gives
        // what it has; foragers who arrive to find it stripped come back and
        // follow another dancer, and until now they simply did not forage at
        // all that day. That was invisible while every patch was a photograph
        // big enough to absorb its share. The countryside made it the dominant
        // effect — forty small wild stands each took a share of the force and
        // wasted most of it, and nectar income fell *sevenfold* with more
        // forage on offer than the colony had ever had.
        //
        // The arithmetic is arranged so that a colony whose patches all absorb
        // their share is completely unaffected: with nothing wasted, `force`
        // and `weightLeft` fall in step and each patch is handed exactly
        // `foragerForce × weight / totalWeight`, which is what it was handed
        // before. Only the surplus is new.
        var force = foragerForce
        var weightLeft = totalWeight

        for slot in floor {
            let index = candidates[slot]
            guard nectarSpace > 0 || pollenSpace > 0 else { break }
            guard force > 0, weightLeft > 0 else { break }

            let assigned = force * (weights[slot] / weightLeft)
            weightLeft -= weights[slot]
            guard assigned > 0.001 else { continue }

            let patch = world.patches[index]
            let efficiency = patch.distanceEfficiency * weatherFactor * seasonFactor

            let wantNectar = min(
                assigned * context.config.nectarPerForager * efficiency,
                nectarSpace
            )
            let wantPollen = min(
                assigned * context.config.pollenPerForager * efficiency * pollenAppetite,
                pollenSpace
            )

            let wasDepleted = patch.isDepleted
            let taken = world.patches[index].harvest(nectar: wantNectar, pollen: wantPollen)
            world.patches[index].recruitedForagers = Int(assigned.rounded())

            totalNectarGathered += taken.nectar
            totalPollenGathered += taken.pollen
            nectarSpace -= taken.nectar
            pollenSpace -= taken.pollen

            // How much of the force this patch could actually use. A stand
            // that gave everything asked of it used all of it; one that was
            // half stripped sends half of them back to the comb, where the
            // next dance is waiting.
            let wanted = wantNectar + wantPollen
            let served = wanted > 0 ? min(1, (taken.nectar + taken.pollen) / wanted) : 0
            let spent = assigned * served
            force -= spent

            // Flying costs honey, and it costs more the further out the patch
            // is. This is what makes a distant rare flower a genuine trade-off
            // rather than a strict upgrade. Charged on the bees who actually
            // worked it: the ones who turned round at a stripped patch are
            // charged at whatever they go on to work instead.
            if taken.nectar > 0 || taken.pollen > 0 {
                flightCost += spent
                    * context.config.flightEnergyPerForager
                    * (1 + patch.distanceMetres / 2_000)
            }

            if !wasDepleted && world.patches[index].isDepleted {
                context.emit(.patchDepleted(patch.id))
            }
        }

        world.hive.resources.add(totalNectarGathered, of: .nectar)
        world.hive.resources.add(totalPollenGathered, of: .pollen)
        world.hive.resources.drain(flightCost, of: .honey)

        // Propolis is collected opportunistically from tree resin.
        if context.rng.chance(context.config.propolisChance * min(20, foragerForce)) {
            world.hive.resources.add(
                1,
                of: .propolis,
                limit: ResourceKind.propolis.uncappedStorageLimit
            )
        }

        world.todayNectarIntake += totalNectarGathered

        accumulateForagerWear(&world, context: context, intensity: weatherFactor)
    }

    /// How keenly the colony is after pollen, 0...1.
    ///
    /// Falls away as the bread bins fill, relative to what the brood will
    /// actually eat over the coming days. A broodless colony wants almost none.
    private func pollenDemandFactor(_ world: World, _ context: TickContext) -> Double {
        let mouths = Double(world.hive.openBroodCount)
        let dailyNeed = mouths * context.config.foodPerLarva * Double(SimClock.ticksPerDay)

        // Even with no brood, a colony keeps a working reserve — it will need
        // it the moment the queen starts laying again.
        let target = max(
            context.config.minimumPollenReserve,
            dailyNeed * context.config.pollenReserveDays
        )

        let stored = world.hive.resources[.pollen] + world.hive.resources[.beeBread]
        guard target > 0 else { return 0 }

        return min(1.0, max(0.0, 1.0 - stored / target))
    }

    /// Foraging is what kills worker bees. A summer forager wears out in a
    /// couple of weeks of hard flying, while a winter bee that never leaves the
    /// cluster lives for months — the difference is entirely wear, not age.
    private func accumulateForagerWear(
        _ world: inout World,
        context: TickContext,
        intensity: Double
    ) {
        let wearPerTick = context.config.forageWearPerTick * intensity
        guard wearPerTick > 0 else { return }

        for index in world.hive.bees.indices where world.hive.bees[index].performs(.foragingBee) {
            world.hive.bees[index].accumulateWear(wearPerTick)
        }
    }
}
