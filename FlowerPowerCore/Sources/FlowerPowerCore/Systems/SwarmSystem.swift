//
//  SwarmSystem.swift
//  FlowerPowerCore
//
//  Swarming is not a failure state — it is how honey bee colonies reproduce.
//  The old queen leaves with most of the flying workforce a few days before the
//  first new queen emerges, and what stays behind is a colony with plenty of
//  comb, plenty of brood, and almost no foragers.
//
//  Absconding is different and much worse: the whole colony walks out and
//  leaves nothing. Real colonies do it when the nest becomes untenable.
//

import Foundation

public struct SwarmSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        if attemptAbscond(&world, &context) { return }
        attemptSwarm(&world, &context)
    }

    // MARK: - Swarming

    private func attemptSwarm(_ world: inout World, _ context: inout TickContext) {
        // A colony swarms only once its replacement is nearly ready. Leaving
        // before then would abandon the nest queenless.
        let swarmCells = world.hive.comb.queenCells.filter { $0.purpose == .swarm }
        guard let leadCell = swarmCells.max(by: { $0.daysDeveloped < $1.daysDeveloped }) else {
            return
        }
        guard leadCell.daysDeveloped >= context.config.swarmDepartureDay else { return }
        guard world.hive.hasLayingQueen else { return }

        // The swarm will not leave in weather it cannot fly in.
        guard world.weather.isFlyingWeather else { return }

        let departing = departingWorkers(world, context)
        guard departing > 0 else { return }

        // The old queen leaves. The colony keeps its queen cells.
        removeQueenForSwarm(&world, &context)
        let lost = removeSwarmWorkers(&world, &context, count: departing)

        // Swarms fill up on honey before they go — a swarm carries several
        // days of stores in the bees' own crops.
        let provisions = Double(lost) * context.config.honeyCarriedPerSwarmBee
        world.hive.resources.drain(provisions, of: .honey)

        world.hive.queenIsMated = false
        world.hive.pheromones.nasonov = 1.0

        context.emit(.swarmed(beesLost: lost))
    }

    /// Roughly 60% of the adult workforce leaves, weighted toward the flying
    /// bees. That is why a swarmed colony stops gathering almost completely.
    private func departingWorkers(_ world: World, _ context: TickContext) -> Int {
        let adults = world.hive.adultWorkerCount
        guard adults >= context.config.swarmMinimumPopulation else { return 0 }

        let share = context.config.swarmDepartureShare
            * (0.85 + 0.3 * world.hive.genetics.swarminess)
        return Int(Double(adults) * min(0.8, share))
    }

    private func removeQueenForSwarm(_ world: inout World, _ context: inout TickContext) {
        guard let index = world.hive.bees.firstIndex(where: {
            $0.kind == .queen && $0.isAdult
        }) else { return }
        world.hive.bees.remove(at: index)
    }

    /// Foragers go with the swarm; house bees and nurses stay to hold the nest.
    private func removeSwarmWorkers(
        _ world: inout World,
        _ context: inout TickContext,
        count: Int
    ) -> Int {
        let candidates = world.hive.bees.indices
            .filter { world.hive.bees[$0].kind == .worker && world.hive.bees[$0].isAdult }
            // Oldest — that is, the flying bees — leave first.
            .sorted { world.hive.bees[$0].daysInStage > world.hive.bees[$1].daysInStage }
            .prefix(count)

        let leaving = Set(candidates)
        guard !leaving.isEmpty else { return 0 }

        for _ in leaving {
            context.emit(.died(.worker, .swarmed))
        }

        world.hive.bees = world.hive.bees.enumerated()
            .filter { !leaving.contains($0.offset) }
            .map(\.element)

        return leaving.count
    }

    // MARK: - Absconding

    /// The colony gives up on the nest entirely and walks out, abandoning comb,
    /// stores and brood. Unlike a swarm this leaves nothing behind, so it is a
    /// loss condition and is deliberately hard to reach.
    ///
    /// Tuned down sharply after a single unrepelled skunk raid on day four was
    /// enough to make a healthy colony abandon a perfectly good nest. Real
    /// colonies abscond under sustained, compounding misery — not one bad night.
    private func attemptAbscond(_ world: inout World, _ context: inout TickContext) -> Bool {
        guard world.hive.hasLayingQueen else { return false }
        guard world.hive.adultWorkerCount >= 15 else { return false }
        guard world.weather.isFlyingWeather else { return false }

        // Only warm-season absconding makes sense; a colony has nowhere to go
        // in autumn and would die on the wing.
        guard context.season == .spring || context.season == .summer else { return false }

        // Only attacks that actually hurt count toward the decision. Ants
        // carrying off a few grams of honey are an irritation, not a reason to
        // abandon a nest — counting every unrepelled nuisance was driving one
        // colony in six out of a perfectly good cavity.
        let relentlessPredation = world.attackHistory
            .filter { record in
                context.day - record.day <= 21
                    && !record.wasRepelled
                    && (record.beesLost > 0 || record.combLost > 0)
            }
            .count

        let diseasePressure = world.hive.pathogens.totalPressure
        let combRuined = world.hive.comb.builtCells < context.config.abscondCombThreshold

        var pressure = 0.0
        if relentlessPredation >= context.config.abscondAttackThreshold {
            pressure += Double(relentlessPredation - context.config.abscondAttackThreshold + 1) * 0.008
        }
        if diseasePressure > 0.8 {
            pressure += (diseasePressure - 0.8) * 0.06
        }
        if combRuined {
            pressure += 0.006
        }

        guard pressure > 0, context.rng.chance(min(context.config.abscondMaximumChance, pressure))
        else { return false }

        let lost = world.hive.adultCount
        world.hive.bees.removeAll()

        context.emit(.absconded(beesLost: lost))
        context.emit(.colonyCollapsed)
        return true
    }
}
