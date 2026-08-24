//
//  ProcessingSystem.swift
//  FlowerPowerCore
//
//  Bees do not manufacture speculatively. Nurses secrete royal jelly for the
//  larvae in front of them; house bees pack only as much bee bread as the nest
//  will eat. Modelling production as workforce-capacity alone drains the honey
//  stores to nothing and starves the colony, which is exactly what the first
//  version of this engine did — so every recipe here is capped by demand.
//

import Foundation

public struct ProcessingSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        ripenNectar(&world, &context)
        packBeeBread(&world, &context)
        secreteRoyalJelly(&world, &context)
    }

    // MARK: - Nectar to honey

    /// Ripening is always worth doing: it is how the colony banks energy, and
    /// it *frees* comb space because honey packs denser than raw nectar. The
    /// limit is evaporation, which stalls in humid air.
    private func ripenNectar(_ world: inout World, _ context: inout TickContext) {
        let concentrators = world.hive.workforce(for: .nectarConcentrator)
        guard concentrators > 0, world.hive.resources[.nectar] > 0 else { return }

        let capacity = concentrators
            * context.config.honeyPerConcentrator
            * world.weather.ripeningFactor
            // Fanning drives evaporation, so fanners speed ripening too.
            * (1 + 0.3 * min(1, world.hive.workforce(for: .fanning) / 20))

        let possible = world.hive.resources[.nectar] / context.config.nectarPerHoney
        let made = min(capacity, possible)
        guard made > 0 else { return }

        world.hive.resources.drain(made * context.config.nectarPerHoney, of: .nectar)
        world.hive.resources.add(made, of: .honey)
    }

    // MARK: - Pollen to bee bread

    private func packBeeBread(_ world: inout World, _ context: inout TickContext) {
        let packers = world.hive.workforce(for: .pollenPacker)
        guard packers > 0 else { return }

        let demand = beeBreadDemand(world, context)
        let deficit = demand - world.hive.resources[.beeBread]
        guard deficit > 0 else { return }

        let capacity = packers * context.config.beeBreadPerPacker
        let ingredientLimit = min(
            world.hive.resources[.pollen] / context.config.pollenPerBeeBread,
            world.hive.resources[.honey] / context.config.honeyPerBeeBread
        )

        let made = min(min(capacity, ingredientLimit), deficit)
        guard made > 0 else { return }

        world.hive.resources.drain(made * context.config.pollenPerBeeBread, of: .pollen)
        world.hive.resources.drain(made * context.config.honeyPerBeeBread, of: .honey)
        world.hive.resources.add(made, of: .beeBread)
    }

    // MARK: - Royal jelly

    /// Royal jelly is secreted from the hypopharyngeal glands of young nurses.
    /// It cannot be stockpiled — it perishes in days — so producing more than
    /// the brood will eat is pure waste of honey and pollen.
    private func secreteRoyalJelly(_ world: inout World, _ context: inout TickContext) {
        let nurses = world.hive.workforce(for: .nurseBee)
        guard nurses > 0 else { return }

        let demand = royalJellyDemand(world, context)
        let deficit = demand - world.hive.resources[.royalJelly]
        guard deficit > 0 else { return }

        let capacity = nurses * context.config.royalJellyPerNurse
        let ingredientLimit = min(
            world.hive.resources[.honey] / context.config.honeyPerRoyalJelly,
            world.hive.resources[.pollen] / context.config.pollenPerRoyalJelly
        )

        let made = min(min(capacity, ingredientLimit), deficit)
        guard made > 0 else { return }

        world.hive.resources.drain(made * context.config.honeyPerRoyalJelly, of: .honey)
        world.hive.resources.drain(made * context.config.pollenPerRoyalJelly, of: .pollen)
        world.hive.resources.add(
            made,
            of: .royalJelly,
            limit: ResourceKind.royalJelly.uncappedStorageLimit
        )
    }

    // MARK: - Demand

    /// Enough bee bread to feed the older larvae for the configured buffer,
    /// plus a little for the adults, who eat pollen for protein in spring.
    private func beeBreadDemand(_ world: World, _ context: TickContext) -> Double {
        let olderLarvae = world.hive.bees.filter {
            $0.stage == .larva && $0.daysInStage >= context.config.royalJellyDays
        }.count

        let broodNeed = Double(olderLarvae)
            * context.config.foodPerLarva
            * Double(SimClock.ticksPerDay)
            * context.config.foodBufferDays

        // House bees also need protein to develop their brood-food glands.
        let adultNeed = Double(world.hive.adultWorkerCount) * 0.02

        return broodNeed + adultNeed
    }

    /// Enough royal jelly for the youngest larvae, the queen — who is fed
    /// nothing else her whole life — and any developing queen cells.
    private func royalJellyDemand(_ world: World, _ context: TickContext) -> Double {
        let youngLarvae = world.hive.bees.filter {
            $0.stage == .larva && $0.daysInStage < context.config.royalJellyDays
        }.count

        let broodNeed = Double(youngLarvae)
            * context.config.foodPerLarva
            * Double(SimClock.ticksPerDay)
            * context.config.foodBufferDays

        // A standing reserve rather than one day's ration, so the queen is
        // reliably fed rather than fed in fits and starts.
        let reserve = context.config.queenJellyReserveDays
        let queenNeed = world.hive.isQueenright
            ? context.config.queenRoyalJellyPerDay * reserve
            : 0

        // Queen cells are flooded with jelly — it is the only thing that makes
        // a queen rather than a worker out of an identical egg.
        let queenCellNeed = Double(world.hive.comb.queenCells.count)
            * context.config.queenCellRoyalJellyPerDay
            * reserve

        return broodNeed + queenNeed + queenCellNeed
    }
}
