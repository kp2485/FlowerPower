//
//  ConstructionSystem.swift
//  FlowerPowerCore
//
//  Bees draw comb only during a nectar flow, and only when they need the room.
//  It costs roughly seven kilos of honey to make one of wax, so a colony that
//  built speculatively would eat itself. Beekeepers rely on this: no flow, no
//  drawn comb, no matter how much foundation you give them.
//

import Foundation

public struct ConstructionSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        let builders = world.hive.workforce(for: .honeycombBuilder)
        guard builders > 0 else { return }

        guard shouldBuild(world, context) else { return }

        secreteWax(&world, &context, builders: builders)
        drawComb(&world, &context, builders: builders)
    }

    /// The conditions a real colony needs before it will build.
    private func shouldBuild(_ world: World, _ context: TickContext) -> Bool {
        // 1. There must be somewhere to put it.
        guard world.hive.comb.canExpand else { return false }

        // 2. Wax-making requires warmth; bees cannot secrete it in the cold.
        guard world.hive.temperatureCelsius >= context.config.minimumWaxTemperature else {
            return false
        }

        // 3. Comb is drawn during the flow and not after it. Beekeepers rely on
        //    this — no flow, no drawn comb, however much foundation you give
        //    them. It also stops a colony spending its winter stores on wax it
        //    cannot eat: at seven honey to one of wax, an autumn building spree
        //    is precisely how a strong colony starves in February.
        guard context.season == .spring || context.season == .summer else { return false }
        guard world.isInFlow(context.config) else { return false }

        // 4. The nest must actually be filling up.
        guard world.hive.combOccupancy >= context.config.buildCongestionThreshold else {
            return false
        }

        // 5. And there must be honey to spare over the reserve.
        return world.hive.resources[.honey] > buildingReserve(world, context)
    }

    /// Honey the colony refuses to convert into wax.
    ///
    /// Rises through the season: by late summer the colony is provisioning for
    /// winter, and comb loses out to stores.
    private func buildingReserve(_ world: World, _ context: TickContext) -> Double {
        let base = context.config.buildHoneyReserve
        guard context.season == .summer else { return base }

        // Ramps from the flat reserve to the full winter requirement across the
        // second half of summer.
        let urgency = max(0, Season.progress(context.day) - 0.5) * 2
        return base + (world.hive.winterStoresRequired - base) * urgency
    }

    private func secreteWax(
        _ world: inout World,
        _ context: inout TickContext,
        builders: Double
    ) {
        // Wax comes out of the flow, not out of the larder.
        //
        // `shouldBuild` establishes that a flow is on. This decides how much of
        // it the colony is willing to turn into wax, and it used to be
        // everything above a flat 25-unit reserve — which, for a colony that
        // has just overwintered, is its entire standing store.
        //
        // What that produced, traced on seed 32676: 60 bees came through
        // winter with 107 units, met a day or two of willow in early spring,
        // and spent 71 of those units drawing 127 cells they had no bees to
        // fill. Stores hit zero on day 390, the whole nest of brood starved
        // with the adults, and the colony was dead on day 416 — at full
        // vitality a fortnight earlier. Six more of the same sixty did it
        // inside the same fortnight.
        //
        // A real colony builds while nectar is arriving faster than it can be
        // stored: the wax scales are secreted by bees gorged on incoming
        // nectar, which is why beekeepers get comb drawn during a flow and
        // never outside one. So the budget is the day's surplus, and a colony
        // whose income stops stops building that day rather than eating its
        // way through its savings.
        let upkeep = Double(world.hive.adultCount)
            * context.config.honeyPerAdult
            * Double(SimClock.ticksPerDay)
        let dailySurplus = max(
            0,
            world.averageNectarIntake / context.config.nectarPerHoney - upkeep
        )
        let fromIncome = dailySurplus
            * context.config.waxIncomeShare
            / Double(SimClock.ticksPerDay)

        // And still never below the reserve the colony needs to stay alive.
        let spendable = min(
            max(0, world.hive.resources[.honey] - context.config.buildHoneyReserve),
            fromIncome
        )
        let capacity = builders * context.config.waxPerBuilder
        let affordable = spendable / context.config.honeyPerWax

        let made = min(capacity, affordable)
        guard made > 0 else { return }

        world.hive.resources.drain(made * context.config.honeyPerWax, of: .honey)
        world.hive.resources.add(made, of: .wax, limit: ResourceKind.wax.uncappedStorageLimit)
    }

    private func drawComb(
        _ world: inout World,
        _ context: inout TickContext,
        builders: Double
    ) {
        // Colonies short of drone comb will chew worker comb into drone comb,
        // so drone shortage takes priority.
        let type: CellType = world.hive.comb.needsDroneComb ? .drone : .worker

        let affordable = Int(world.hive.resources[.wax] / type.waxCost)
        let workRate = Int(builders * context.config.cellsPerBuilderPerTick) + 1
        let wanted = min(affordable, workRate)
        guard wanted > 0 else { return }

        let built = world.hive.comb.build(wanted, as: type)
        guard built > 0 else { return }

        world.hive.resources.drain(Double(built) * type.waxCost, of: .wax)
        context.emit(.cellsBuilt(count: built, type: type))
    }
}
