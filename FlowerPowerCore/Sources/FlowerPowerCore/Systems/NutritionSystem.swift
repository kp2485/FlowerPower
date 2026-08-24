//
//  NutritionSystem.swift
//  FlowerPowerCore
//
//  Who eats, what, and what happens when there is not enough. A starving
//  colony does not fail evenly: it abandons brood first, then drones, and the
//  adults go last — which is why a hive can look populous right up until the
//  week it dies.
//

import Foundation

public struct NutritionSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        feedAdults(&world, &context)
        feedQueen(&world, &context)
        feedBrood(&world, &context)
        feedQueenCells(&world, &context)
    }

    // MARK: - Adults

    private func feedAdults(_ world: inout World, _ context: inout TickContext) {
        // The queen is excluded deliberately: she eats royal jelly and nothing
        // else her entire adult life, and `feedQueen` handles her.
        //
        // Including her here charged her twice and, worse, applied the general
        // starvation damage to her every time the colony ran short of honey.
        // Her condition ground down to nothing over a season, which halved her
        // effective lifespan — so she died of "old age" in her second spring,
        // usually while the colony was broodless and could not replace her.
        // It was the single largest cause of colony failure.
        let feeders = world.hive.bees.indices.filter {
            world.hive.bees[$0].isAdult && world.hive.bees[$0].kind != .queen
        }
        guard !feeders.isEmpty else { return }

        // Flying is expensive; clustering in the cold is expensive; sitting
        // still in a warm hive is cheap.
        let activity = world.weather.isFlyingWeather && context.isDaylight ? 1.0 : 0.6
        let needed = Double(feeders.count) * context.config.honeyPerAdult * activity

        let eaten = world.hive.resources.drain(needed, of: .honey)
        guard eaten < needed * 0.6 else { return }

        context.emit(.starving)

        // Adults tolerate hunger for a while before dying, losing condition
        // first. Drones are pushed out before any worker goes hungry.
        let shortfall = 1 - (needed > 0 ? eaten / needed : 1)
        for index in feeders {
            world.hive.bees[index].damage(shortfall * context.config.starvationDamagePerTick)
        }

        if shortfall > 0.85 {
            let toll = Int(Double(feeders.count) * shortfall * context.config.adultStarvationRate)
            BroodMortality.cullAdults(&world, &context, count: toll, cause: .starvation)
        }
    }

    // MARK: - Queen

    /// The queen eats nothing but royal jelly her entire adult life, and her
    /// laying rate collapses without it.
    private func feedQueen(_ world: inout World, _ context: inout TickContext) {
        guard world.hive.isQueenright else { return }

        let needed = context.config.queenRoyalJellyPerDay / Double(SimClock.ticksPerDay)
        let fed = world.hive.resources.drain(needed, of: .royalJelly)

        guard needed > 0 else { return }
        let ratio = fed / needed

        guard let queenIndex = world.hive.bees.firstIndex(where: {
            $0.kind == .queen && $0.isAdult
        }) else { return }

        if ratio < 0.5 {
            world.hive.bees[queenIndex].damage(context.config.queenStarvationDamagePerTick)
        } else if ratio > 0.9 {
            world.hive.bees[queenIndex].recover(context.config.queenRecoveryPerTick)
        }
    }

    // MARK: - Brood

    private func feedBrood(_ world: inout World, _ context: inout TickContext) {
        let larvaIndices = world.hive.bees.indices.filter { world.hive.bees[$0].stage == .larva }
        guard !larvaIndices.isEmpty else { return }

        // Eggs and pupae do not feed; only larvae do.
        let young = larvaIndices.filter {
            world.hive.bees[$0].daysInStage < context.config.royalJellyDays
        }
        let older = larvaIndices.filter {
            world.hive.bees[$0].daysInStage >= context.config.royalJellyDays
        }

        let jellyRatio = ration(
            &world,
            count: young.count,
            resource: .royalJelly,
            perHead: context.config.foodPerLarva
        )
        let breadRatio = ration(
            &world,
            count: older.count,
            resource: .beeBread,
            perHead: context.config.foodPerLarva
        )

        // Underfed larvae emerge as undersized adults with short lives, even
        // when they survive — a real and underappreciated failure mode.
        applyRation(&world, indices: young, ratio: jellyRatio, context: context)
        applyRation(&world, indices: older, ratio: breadRatio, context: context)

        let worstRatio = min(
            young.isEmpty ? 1 : jellyRatio,
            older.isEmpty ? 1 : breadRatio
        )
        guard worstRatio < 0.75 else { return }

        context.emit(.starving)

        // Nurses cannibalise brood they cannot feed, recovering some protein.
        // It is grim, and it is what actually happens.
        let severity = 1 - worstRatio
        BroodMortality.cull(
            &world,
            &context,
            fraction: severity * context.config.broodStarvationRate,
            cause: .starvation
        )
    }

    /// Queen cells are fed lavishly and continuously; a cell that runs short
    /// produces a poor queen or fails outright.
    private func feedQueenCells(_ world: inout World, _ context: inout TickContext) {
        guard !world.hive.comb.queenCells.isEmpty else { return }

        let needed = Double(world.hive.comb.queenCells.count)
            * context.config.queenCellRoyalJellyPerDay
            / Double(SimClock.ticksPerDay)

        let fed = world.hive.resources.drain(needed, of: .royalJelly)
        guard needed > 0, fed < needed * 0.4 else { return }

        // Starved queen cells are torn down — but rarely, and this runs every
        // tick. At five per cent per tick a cell had a seventy per cent chance
        // of being destroyed each day, so an emergency queen essentially never
        // survived the twelve days to emergence and a queenless colony was
        // always doomed however much young brood it had.
        if context.rng.chance(context.config.queenCellAbandonChancePerTick) {
            world.hive.comb.queenCells.removeLast()
        }
    }

    // MARK: - Helpers

    /// Draws rations for `count` mouths and reports the fraction actually met.
    private func ration(
        _ world: inout World,
        count: Int,
        resource: ResourceKind,
        perHead: Double
    ) -> Double {
        guard count > 0 else { return 1 }
        let needed = Double(count) * perHead
        let taken = world.hive.resources.drain(needed, of: resource)
        return needed > 0 ? taken / needed : 1
    }

    private func applyRation(
        _ world: inout World,
        indices: [Int],
        ratio: Double,
        context: TickContext
    ) {
        guard ratio < 0.95 else {
            for index in indices {
                world.hive.bees[index].recover(context.config.broodRecoveryPerTick)
            }
            return
        }

        let damage = (1 - ratio) * context.config.malnutritionDamagePerTick
        for index in indices {
            world.hive.bees[index].damage(damage)
        }
    }
}
