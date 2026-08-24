//
//  PheromoneSystem.swift
//  FlowerPowerCore
//
//  Nobody is in charge of a beehive. Every colony-level decision — whether to
//  swarm, whether to replace the queen, how hard to forage — emerges from
//  chemical gradients that individual bees respond to locally.
//
//  Queen mandibular pheromone is the load-bearing one. The queen produces a
//  roughly fixed amount and it spreads by bee-to-bee contact, so the
//  concentration each worker experiences is diluted by colony size. That single
//  fact explains why colonies swarm when they get big: the queen has not
//  changed, but there are now too many bees for her signal to reach.
//

import Foundation

public struct PheromoneSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        updateQueenSignal(&world, context)
        updateBroodSignal(&world, context)
        decayTransientSignals(&world, context)
    }

    private func updateQueenSignal(_ world: inout World, _ context: TickContext) {
        let target: Double

        if let queen = world.hive.queen {
            // Output falls as the queen ages and as her condition declines.
            let ageFraction = Double(queen.daysInStage)
                / Double(BeeKind.queen.baseAdultLifespanDays())
            let vigour = queen.vitality * (1.0 - 0.55 * min(1, ageFraction))

            // A virgin queen produces very little until she is mated.
            let maturity = world.hive.queenIsMated ? 1.0 : 0.25

            // Dilution by colony size: the same queen signal spread over more
            // bees means less of it reaches each one.
            let dilution = 1.0 / (1.0 + Double(world.hive.adultCount) / context.config.pheromoneDilutionScale)

            target = min(1.0, vigour * maturity * dilution * context.config.queenPheromoneOutput)
        } else {
            target = 0
        }

        // Pheromone concentration moves smoothly; the colony takes days to
        // notice a queen is gone, which is exactly the real behaviour.
        world.hive.pheromones.queenMandibular += (target - world.hive.pheromones.queenMandibular)
            * context.config.pheromoneResponseRate
    }

    /// Open brood signals that there are mouths to feed, and drives foraging.
    private func updateBroodSignal(_ world: inout World, _ context: TickContext) {
        let openBrood = Double(world.hive.openBroodCount)
        let target = min(1.0, openBrood / context.config.broodPheromoneScale)

        world.hive.pheromones.brood += (target - world.hive.pheromones.brood)
            * context.config.pheromoneResponseRate
    }

    private func decayTransientSignals(_ world: inout World, _ context: TickContext) {
        world.hive.pheromones.alarm *= context.config.alarmDecayPerTick
        world.hive.pheromones.nasonov *= context.config.nasonovDecayPerTick

        if world.hive.pheromones.alarm < 0.001 { world.hive.pheromones.alarm = 0 }
        if world.hive.pheromones.nasonov < 0.001 { world.hive.pheromones.nasonov = 0 }
    }
}
