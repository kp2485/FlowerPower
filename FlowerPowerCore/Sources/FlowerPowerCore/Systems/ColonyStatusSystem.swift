//
//  ColonyStatusSystem.swift
//  FlowerPowerCore
//
//  Watches the colony as a whole and raises the handful of signals the player
//  actually needs: the flow has started, the dearth has begun, winter stores
//  are short, the colony is gone. Runs last in the pipeline so it sees the
//  finished state of the day.
//

import Foundation

public struct ColonyStatusSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        detectFlowAndDearth(&world, &context)
        warnAboutWinterStores(&world, &context)
        detectCollapse(&world, &context)
        trimComb(&world, &context)
    }

    /// A nectar flow changes colony behaviour wholesale, and the player should
    /// know it has started — it is the window for building comb and splitting.
    private func detectFlowAndDearth(_ world: inout World, _ context: inout TickContext) {
        guard world.recentNectarIntake.count >= 2 else { return }

        let today = world.recentNectarIntake.last ?? 0
        let yesterday = world.recentNectarIntake[world.recentNectarIntake.count - 2]
        let threshold = Double(world.hive.adultCount) * context.config.flowThresholdPerBee

        if today > threshold && yesterday <= threshold {
            context.emit(.nectarFlowBegan)
        } else if world.isInDearth(context.config)
            && yesterday > Double(world.hive.adultCount) * context.config.dearthThresholdPerBee {
            context.emit(.dearth)
        }
    }

    /// The number that decides whether the colony sees spring. Warn while there
    /// is still season enough left to do something about it.
    private func warnAboutWinterStores(_ world: inout World, _ context: inout TickContext) {
        let season = context.season
        guard season == .autumn else { return }

        // Only warn once the colony should plausibly have provisioned, and
        // while there is still time to fix it.
        let progress = Season.progress(context.day)
        guard progress > 0.25 else { return }

        let have = world.hive.resources.edibleEnergy
        let need = world.hive.winterStoresRequired
        guard have < need else { return }

        // Weekly, not daily — a warning every day is noise.
        guard context.day % 7 == 0 else { return }
        context.emit(.winterStoresLow(have: have, need: need))
    }

    private func detectCollapse(_ world: inout World, _ context: inout TickContext) {
        // Only when the colony has actually ended, not when it is merely
        // doomed. This event is what puts "The colony has collapsed." in the
        // catch-up report and what flips the interface to offering a fresh
        // start, and both of those are wrong while there are still bees in the
        // box — a colony below critical mass usually dies, but it is the
        // player's to lose, and occasionally an emergency queen does make it
        // back mated.
        //
        // A doomed colony is reported as `critical` with an alert saying why,
        // which is the honest version of the same news.
        guard world.hive.isCollapsed else { return }
        context.emit(.colonyCollapsed)
    }

    /// Comb the colony is too small to patrol is lost to wax moths and mould.
    /// This is what makes a dwindling colony's decline accelerate.
    private func trimComb(_ world: inout World, _ context: inout TickContext) {
        let bees = Double(world.hive.adultCount)
        let maintainable = bees * context.config.cellsMaintainedPerBee
        let excess = Double(world.hive.comb.builtCells) - maintainable
        guard excess > 0 else { return }

        let decay = Int(excess * context.config.combDecayRate)
        guard decay > 0 else { return }

        let lost = world.hive.comb.destroy(decay, of: .worker)
            + world.hive.comb.destroy(max(0, decay - world.hive.comb[.worker]), of: .drone)

        if lost > 0 {
            context.emit(.combLost(count: lost))
        }
    }
}
