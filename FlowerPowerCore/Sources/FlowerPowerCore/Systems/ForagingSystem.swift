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
        let foragerForce = world.hive.workforce(for: .foragingBee)
        guard foragerForce > 0 else { return }

        // Only patches in bloom, in range, and not stripped are worth dancing for.
        let candidates = world.patches.indices.filter { index in
            let patch = world.patches[index]
            return patch.isInBloom(during: season)
                && patch.isWithinRange
                && !patch.isDepleted
                && patch.forageQuality > 0
        }
        guard !candidates.isEmpty else { return }

        // Recruitment is superlinear in quality: a patch twice as good attracts
        // far more than twice the dancers. This is what makes the colony
        // converge on the best forage rather than spreading itself evenly.
        let weights = candidates.map { index in
            pow(world.patches[index].forageQuality, context.config.danceRecruitmentExponent)
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return }

        // Comb space limits how much unripened nectar the colony can accept. A
        // "honey bound" colony physically cannot take more in, which is one of
        // the real triggers for swarming.
        let freeCells = Double(world.hive.freeCells)
        var nectarSpace = max(0, freeCells * ResourceKind.nectar.unitsPerCell)
        var pollenSpace = max(0, freeCells * ResourceKind.pollen.unitsPerCell)

        // Pollen collection is demand-driven in a way nectar is not. Nectar
        // becomes honey, which keeps forever and is the colony's savings, so
        // more is always welcome. Pollen is perishable protein for brood, and a
        // colony with its bread bins full simply switches its foragers over to
        // nectar. Without this the nest fills with pollen it will never eat,
        // crowding out the very brood the pollen was for.
        let pollenAppetite = pollenDemandFactor(world, context)

        let seasonFactor = season.forageMultiplier
        var totalNectarGathered = 0.0
        var totalPollenGathered = 0.0
        var flightCost = 0.0

        for (slot, index) in candidates.enumerated() {
            guard nectarSpace > 0 || pollenSpace > 0 else { break }

            let share = weights[slot] / totalWeight
            let assigned = foragerForce * share
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

            // Flying costs honey, and it costs more the further out the patch
            // is. This is what makes a distant rare flower a genuine trade-off
            // rather than a strict upgrade.
            if taken.nectar > 0 || taken.pollen > 0 {
                flightCost += assigned
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
