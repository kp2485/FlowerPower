//
//  ThreatSystem.swift
//  FlowerPowerCore
//
//  Defence. Guards meet what comes to the entrance; nothing meets what takes
//  foragers out at the flowers. The site matters enormously — a nest under an
//  open branch is indefensible no matter how many guards it posts — which is
//  what makes the choice of hive location a real strategic decision rather
//  than flavour text.
//

import Foundation

public struct ThreatSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        // A siege that has run its course resolves with whatever posture the
        // colony holds today. Until then, nothing else comes to the door —
        // one crisis at a time is plenty, and it keeps the decision clear.
        if let threat = world.activeThreat {
            if context.day >= threat.resolvesOnDay {
                world.activeThreat = nil
                resolveAttack(threat.predator, &world, &context)
                context.emit(.threatEnded(threat.predator))
            }
        } else {
            for predator in Predator.allCases {
                guard predator.activeSeasons.contains(context.season) else { continue }
                guard context.rng.chance(encounterChance(predator, world, context)) else { continue }

                if predator.hasDecisionWindow {
                    // The window opens. The player has until it closes.
                    let threat = ActiveThreat(
                        predator: predator,
                        beganOnDay: context.day,
                        resolvesOnDay: context.day + predator.siegeDays
                    )
                    world.activeThreat = threat
                    world.hive.pheromones.alarm = min(1.0, world.hive.pheromones.alarm + 0.3)
                    context.emit(.threatBegan(predator, resolvesOnDay: threat.resolvesOnDay))
                    break
                } else {
                    // A bear is over in a night and there is nothing to decide.
                    resolveAttack(predator, &world, &context)
                }
            }
        }

        // Alarm pheromone fades over the following days.
        world.hive.pheromones.alarm *= 0.6
    }

    // MARK: - Likelihood

    private func encounterChance(
        _ predator: Predator,
        _ world: World,
        _ context: TickContext
    ) -> Double {
        var chance = predator.dailyEncounterChance

        // Ground-dwelling raiders find some sites far more easily than others.
        if predator.attackStyle == .entrance || predator.attackStyle == .catastrophic {
            chance *= 0.4 + world.hive.location.type.groundPredatorExposure
        }

        // Field ambushers only get a chance when the bees are actually out.
        if predator.attackStyle == .field {
            guard world.weather.isFlyingWeather else { return 0 }
            let foragers = Double(world.hive.count(performing: .foragingBee))
            chance *= min(2.0, foragers / 25.0)
        }

        // Wax moths, beetles, mice and robbers are opportunists: they only take
        // hold once the colony is too weak to patrol its own nest. A colony of
        // any real size shrugs them off, so the multiplier drops below one well
        // before the workforce is large.
        if predator.exploitsWeakColonies {
            let strength = min(1.0, Double(world.hive.adultWorkerCount) / 60.0)
            chance *= max(0.05, 1.8 * (1 - strength))
        }

        // A rich hive is a more attractive target.
        if !predator.storesLossFraction.isEmpty {
            chance *= 0.6 + min(1.5, world.hive.resources[.honey] / 200.0)
        }

        // A narrowed entrance is what keeps a mouse out of a winter cluster,
        // and it turns away most of what would otherwise walk in.
        let narrowed = world.entranceSealed || world.posture == .narrowEntrance
        if narrowed {
            switch predator {
            case .mouse: chance *= context.config.sealedEntranceMouseFactor
            case .wasp, .hornet, .robberBee, .ant: chance *= 0.5
            default: break
            }
        }

        // Woodpeckers open a nest up in hard frost, when the cluster cannot
        // come out to meet them, and not otherwise.
        if predator == .woodpecker, world.weather.temperatureCelsius > 2 {
            return 0
        }

        return min(0.9, chance)
    }

    // MARK: - Resolution

    private func resolveAttack(
        _ predator: Predator,
        _ world: inout World,
        _ context: inout TickContext
    ) {
        context.emit(.attacked(predator))
        world.hive.pheromones.alarm = min(1.0, world.hive.pheromones.alarm + 0.6)

        let repelled = attemptDefence(predator, &world, &context)

        var beesLost = 0
        var storesLost = 0.0
        var combLost = 0

        if repelled {
            context.emit(.attackRepelled(predator))
            // Defending is not free. Bees that sting a mammal die doing it.
            // Stinging costs the stinger. An alarmed colony stings more
            // readily and loses more bees doing it, which is what keeps the
            // defence boost above from being free.
            let stinging = 1 + world.hive.pheromones.alarm * context.config.alarmCasualtyRate
            beesLost = Int(
                (Double(defenderCasualties(predator, world, &context))
                    * world.posture.casualtyMultiplier() * stinging).rounded()
            )
            BroodMortality.cullAdults(&world, &context, count: beesLost, cause: .stungIntruder)
        } else {
            beesLost = applyBeeLosses(predator, &world, &context)
            storesLost = applyStoresLosses(predator, &world, &context)
            combLost = applyCombLosses(predator, &world, &context)

            if storesLost > 0 {
                context.emit(.raidSucceeded(predator, storesLost: storesLost))
            }
        }

        world.recordAttack(AttackRecord(
            id: context.ids.next(),
            predator: predator,
            day: context.day,
            wasRepelled: repelled,
            beesLost: beesLost,
            storesLost: storesLost,
            combLost: combLost
        ))
    }

    /// Guards, site defensibility and colony temperament versus the attacker's
    /// threat level. A bear is simply unstoppable, and so is anything that
    /// never comes to the entrance.
    private func attemptDefence(
        _ predator: Predator,
        _ world: inout World,
        _ context: inout TickContext
    ) -> Bool {
        guard predator.isDeterredByGuards else { return false }
        guard predator.threatLevel < 1.0 else { return false }

        let guards = world.hive.workforce(for: .guardBee)
        // In a real emergency the whole colony turns out, not just the guards.
        let reserves = world.hive.workforce(for: .fanning) * 0.3
            + world.hive.workforce(for: .honeycombBuilder) * 0.2

        let defenderStrength = (guards + reserves)
            * (0.5 + world.hive.genetics.defensiveness)
            * context.config.guardStrength

        // Nocturnal raiders arrive when the colony is clustered and sluggish.
        let alertness = predator.isNocturnal ? 0.55 : 1.0

        // Cold bees cannot fly to sting.
        let mobility = world.hive.temperatureCelsius > 14 ? 1.0 : 0.4

        // Alarm pheromone. Raised the moment the raider arrives, a few lines
        // above this, which is the right order: the guards call and the colony
        // answers. Below any posture the player could choose, on purpose —
        // instinct is a real answer, and a decision has to beat it.
        let alarm = 1 + world.hive.pheromones.alarm * context.config.alarmDefenceBoost

        let defence = defenderStrength * alertness * mobility * alarm
            * (0.6 + world.hive.location.type.defensibility)
            * world.posture.defenceMultiplier(against: predator.attackStyle)
            // Even without a posture, a sealed winter entrance is easier to
            // hold than an open one.
            * (world.entranceSealed && predator.attackStyle == .entrance ? 1.2 : 1.0)

        let attack = predator.threatLevel * context.config.predatorStrength

        guard defence + attack > 0 else { return false }
        let odds = defence / (defence + attack)

        return context.rng.chance(odds)
    }

    private func defenderCasualties(
        _ predator: Predator,
        _ world: World,
        _ context: inout TickContext
    ) -> Int {
        // Stinging a mammal is suicide; stinging a wasp is not.
        let isMammalian: Bool
        switch predator {
        case .bear, .badger, .skunk, .raccoon, .opossum, .mouse, .human: isMammalian = true
        default: isMammalian = false
        }

        let rate = isMammalian ? 0.02 : 0.006
        let base = Double(world.hive.adultWorkerCount) * rate * predator.threatLevel
        return max(0, Int((base * (0.5 + context.rng.unitValue())).rounded()))
    }

    private func applyBeeLosses(
        _ predator: Predator,
        _ world: inout World,
        _ context: inout TickContext
    ) -> Int {
        var fraction = context.sample(predator.beeLossFraction)
        if predator.attackStyle == .field {
            fraction *= world.posture.fieldLossMultiplier()
        }
        guard fraction > 0 else { return 0 }

        let toll = Int((Double(world.hive.adultCount) * fraction).rounded())
        guard toll > 0 else { return 0 }

        // Field ambushers eat foragers specifically, which hurts far more than
        // the raw number suggests — those are the bees bringing food in.
        let excludeQueen = predator.attackStyle != .catastrophic
        return BroodMortality.cullAdults(
            &world, &context,
            count: toll,
            cause: .predation,
            excludeQueen: excludeQueen
        )
    }

    private func applyStoresLosses(
        _ predator: Predator,
        _ world: inout World,
        _ context: inout TickContext
    ) -> Double {
        let fraction = context.sample(predator.storesLossFraction)
        guard fraction > 0 else { return 0 }

        var taken = 0.0
        for kind in [ResourceKind.honey, .beeBread, .pollen, .nectar] {
            taken += world.hive.resources.drain(world.hive.resources[kind] * fraction, of: kind)
        }
        return taken
    }

    private func applyCombLosses(
        _ predator: Predator,
        _ world: inout World,
        _ context: inout TickContext
    ) -> Int {
        let fraction = context.sample(predator.combLossFraction)
            * world.posture.combLossMultiplier()
        guard fraction > 0 else { return 0 }

        let workerLoss = Int(Double(world.hive.comb[.worker]) * fraction)
        let droneLoss = Int(Double(world.hive.comb[.drone]) * fraction)

        let destroyed = world.hive.comb.destroy(workerLoss, of: .worker)
            + world.hive.comb.destroy(droneLoss, of: .drone)

        if destroyed > 0 {
            context.emit(.combLost(count: destroyed))
        }
        return destroyed
    }
}

private extension ClosedRange where Bound == Double {
    /// A range of zero width contributes nothing, which several predators use
    /// to opt out of a loss category entirely.
    var isEmpty: Bool { upperBound <= 0 }
}
