//
//  DiseaseSystem.swift
//  FlowerPowerCore
//
//  Varroa deserves the detail it gets here, because it is the reason most
//  colonies die and because its dynamics are genuinely interesting: the mite
//  can only breed inside capped brood, so mite growth tracks brood rearing.
//  Through summer the colony out-breeds the mites. Then brood rearing winds
//  down in autumn while the mite population does not, the ratio inverts, and
//  the winter bees — the ones that have to live six months — are reared under
//  the heaviest mite pressure of the year. The colony looks fine in September
//  and is dead by January.
//

import Foundation

public struct DiseaseSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        introducePathogens(&world, &context)
        growInfections(&world, &context)
        applyHygienicBehaviour(&world, &context)
        applyNaturalRecovery(&world, &context)
        applyVirusCoupling(&world, &context)
        applyMortality(&world, &context)
        reportThresholds(&world, &context)
    }

    // MARK: - Arrival

    /// Mites and pathogens arrive on drifting bees, on robbers, and on foragers
    /// sharing flowers with infected colonies. A hive is never truly isolated.
    private func introducePathogens(_ world: inout World, _ context: inout TickContext) {
        guard context.season != .winter else { return }

        // Robbing and drifting scale with how much traffic the colony has.
        let exposure = min(1.0, Double(world.hive.count(performing: .foragingBee)) / 60.0)

        for pathogen in Pathogen.allCases {
            guard world.hive.pathogens[pathogen] <= 0 else { continue }

            var chance = context.config.pathogenArrivalChance(for: pathogen) * exposure

            // A good propolis envelope is genuinely antimicrobial.
            chance *= (1 - 0.4 * world.hive.propolisEnvelope)

            // Damp nests breed chalkbrood.
            if pathogen == .chalkbrood, world.hive.humidity > 0.75 {
                chance *= 3
            }

            if context.rng.chance(chance) {
                world.hive.pathogens[pathogen] = context.config.pathogenSeedLevel
                context.emit(.infectionDetected(pathogen))
            }
        }
    }

    // MARK: - Growth

    private func growInfections(_ world: inout World, _ context: inout TickContext) {
        let cappedBrood = Double(world.hive.cappedBroodCount)
        let adults = Double(max(1, world.hive.adultCount))

        for (pathogen, level) in world.hive.pathogens.active {
            var growth = pathogen.baseGrowthRate

            switch pathogen {
            case .varroa:
                // Mites reproduce only in capped brood. No brood, no growth —
                // which is why a broodless period is the one natural check on
                // them.
                let broodAvailability = min(1.5, cappedBrood / max(20, adults * 0.3))
                growth *= broodAvailability

                // Drone brood stays capped days longer and is strongly
                // preferred: mites breed far faster where there is drone comb.
                growth *= 1 + world.hive.comb.droneShare * 1.6

            case .nosema:
                // A gut parasite, worst when bees are confined and cannot
                // cleanse — cold, wet, shut-in weather.
                if !world.weather.isFlyingWeather { growth *= 2.2 }
                if context.season == .winter { growth *= 1.8 }

            case .chalkbrood:
                // A fungus of damp, chilled brood nests.
                if world.hive.humidity > 0.7 { growth *= 2.0 }
                if world.hive.temperatureCelsius < 33 { growth *= 1.8 }

            case .deformedWingVirus:
                // Driven almost entirely by its vector; see `applyVirusCoupling`.
                growth *= 0.4 + world.hive.pathogens[.varroa] * 2.0

            case .americanFoulbrood:
                // A spore-former that thrives regardless.
                break
            }

            // Genetic resistance and diversity slow everything.
            growth *= (1 - 0.7 * world.hive.genetics.diseaseResistance)

            // Density-dependent saturation.
            let capacity = 1.0
            let newLevel = level + growth * level * (1 - level / capacity)
            world.hive.pathogens[pathogen] = newLevel
        }
    }

    /// Deformed wing virus is carried by varroa. Below roughly a 3% mite load
    /// it stays latent; above it, the virus takes off — and it is the virus,
    /// not the mite, that empties the hive.
    private func applyVirusCoupling(_ world: inout World, _ context: inout TickContext) {
        let varroa = world.hive.pathogens[.varroa]
        guard varroa > PathogenLoad.varroaVirusThreshold else { return }

        let excess = varroa - PathogenLoad.varroaVirusThreshold
        let seeded = world.hive.pathogens[.deformedWingVirus]

        if seeded <= 0 {
            world.hive.pathogens[.deformedWingVirus] = context.config.pathogenSeedLevel
            context.emit(.infectionDetected(.deformedWingVirus))
        } else {
            world.hive.pathogens[.deformedWingVirus] = seeded + excess * 0.12
        }
    }

    // MARK: - Defence

    /// Hygienic workers detect diseased brood through the cappings, uncap it,
    /// and haul it out. It is the colony's own immune system, it is heritable,
    /// and it is the single most valuable trait a bee breeder selects for.
    private func applyHygienicBehaviour(_ world: inout World, _ context: inout TickContext) {
        let hygiene = world.hive.genetics.hygienicBehaviour
        let cleaners = world.hive.workforce(for: .cellCleaner)
            + world.hive.workforce(for: .mortuary)
        guard cleaners > 0, hygiene > 0 else { return }

        let effort = min(1.0, cleaners / max(10, Double(world.hive.broodCount) * 0.3))

        for (pathogen, level) in world.hive.pathogens.active
        where pathogen.respondsToHygiene {
            let removed = level * hygiene * effort * context.config.hygienicRemovalRate
            let remaining = level - removed
            world.hive.pathogens[pathogen] = remaining

            if remaining <= 0.005 && level > 0.005 {
                context.emit(.infectionCleared(pathogen))
            }
        }
    }

    /// Infections recede as well as grow, and most of them have a specific
    /// condition that clears them.
    ///
    /// Nosema is the clearest case and the one this was written for: it is a
    /// gut parasite spread by faecal contamination, so it builds while the bees
    /// are shut in and clears once they can fly out and cleanse. Without a
    /// recovery path it simply ratcheted to total infection and stayed there,
    /// killing every colony in its second summer.
    private func applyNaturalRecovery(_ world: inout World, _ context: inout TickContext) {
        for (pathogen, level) in world.hive.pathogens.active {
            // Mites do not leave on their own, and foulbrood spores survive in
            // the comb for decades. Neither gets the baseline grooming
            // recovery — only hygienic behaviour touches them. Granting them a
            // background decay quietly made varroa a non-problem.
            let clearsNaturally = pathogen != .varroa && pathogen != .americanFoulbrood
            var recovery = clearsNaturally ? context.config.pathogenBaseRecovery : 0

            switch pathogen {
            case .nosema:
                if world.weather.isFlyingWeather {
                    recovery += context.config.nosemaCleansingRecovery
                }

            case .chalkbrood:
                // A dry, properly warmed brood nest is the cure.
                if world.hive.humidity < 0.65,
                   world.hive.temperatureCelsius >= context.config.minimumBroodTemperature {
                    recovery += 0.05
                }

            case .deformedWingVirus:
                // The virus subsides once its vector is back under control.
                if world.hive.pathogens[.varroa] < PathogenLoad.varroaVirusThreshold {
                    recovery += 0.07
                }

            case .varroa, .americanFoulbrood:
                break
            }

            // A well-fed colony behind a good propolis envelope fights harder.
            recovery *= 1 + world.hive.propolisEnvelope * 0.5
            recovery *= 0.5 + world.hive.averageVitality

            let remaining = level * (1 - min(0.9, recovery))
            world.hive.pathogens[pathogen] = remaining

            if remaining <= 0.005 && level > 0.005 {
                context.emit(.infectionCleared(pathogen))
            }
        }
    }

    // MARK: - Harm

    private func applyMortality(_ world: inout World, _ context: inout TickContext) {
        let resistance = world.hive.genetics.diseaseResistance

        for (pathogen, level) in world.hive.pathogens.active {
            let severity = level * (1 - 0.5 * resistance)

            // Brood damage. Pupae parasitised by varroa emerge with shrivelled
            // wings — alive, in the hive, and useless as foragers.
            if pathogen == .varroa || pathogen == .deformedWingVirus {
                let damage = severity * context.config.viralBroodDamage
                for index in world.hive.bees.indices
                where world.hive.bees[index].stage == .pupa {
                    world.hive.bees[index].damage(damage)
                }
            }

            let broodLoss = severity * pathogen.broodLethality
            BroodMortality.cull(&world, &context, fraction: broodLoss, cause: .disease)

            let adultLoss = severity * pathogen.adultLethality
            let toll = Int((Double(world.hive.adultCount) * adultLoss).rounded())
            if toll > 0 {
                BroodMortality.cullAdults(&world, &context, count: toll, cause: .disease)
            } else if context.rng.chance(Double(world.hive.adultCount) * adultLoss) {
                BroodMortality.cullAdults(&world, &context, count: 1, cause: .disease)
            }
        }
    }

    private func reportThresholds(_ world: inout World, _ context: inout TickContext) {
        for (pathogen, level) in world.hive.pathogens.active
        where level >= context.config.criticalInfectionLevel {
            context.emit(.infectionCritical(pathogen))
        }
    }
}
