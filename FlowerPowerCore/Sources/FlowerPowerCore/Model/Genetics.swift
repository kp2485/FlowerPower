//
//  Genetics.swift
//  FlowerPowerCore
//
//  A queen mates once, on a single flight, with a dozen or more drones from
//  other colonies. Every worker she ever lays descends from that one flight, so
//  the colony's whole genetic character — its disease resistance, its
//  hygienic behaviour, its temper — is fixed in an afternoon. Features.md
//  called this out: mating with drones from different colonies increases the
//  hive's ability to resist disease.
//

import Foundation

public struct QueenGenetics: Codable, Equatable, Sendable {

    /// Number of drones the queen mated with. Each contributes a patriline, and
    /// diversity across patrilines is what buys disease resistance.
    public var patrilines: Int

    /// Propensity to detect and remove diseased brood, 0...1. The single most
    /// valuable trait a colony can have against varroa and foulbrood.
    public var hygienicBehaviour: Double

    /// 0 is placid, 1 is fiercely defensive. Defensive colonies repel raiders
    /// better but lose more bees doing it.
    public var defensiveness: Double

    /// Egg-laying vigour, scaling the queen's daily output.
    public var fecundity: Double

    /// Tendency to build up fast and swarm, versus staying compact.
    public var swarminess: Double

    /// Winter hardiness — how efficiently the cluster holds heat.
    public var thriftiness: Double

    public init(
        patrilines: Int = 12,
        hygienicBehaviour: Double = 0.5,
        defensiveness: Double = 0.5,
        fecundity: Double = 1.0,
        swarminess: Double = 0.5,
        thriftiness: Double = 0.5
    ) {
        self.patrilines = patrilines
        self.hygienicBehaviour = hygienicBehaviour
        self.defensiveness = defensiveness
        self.fecundity = fecundity
        self.swarminess = swarminess
        self.thriftiness = thriftiness
    }

    /// Typical well-mated queen.
    public static let standard = QueenGenetics()

    /// Diversity across patrilines, 0...1. A poorly mated queen produces a
    /// genetically uniform workforce that a single pathogen can sweep through.
    public var geneticDiversity: Double {
        // Returns diminish past roughly 20 matings, which is where the real
        // benefit curve flattens too.
        min(1.0, Double(patrilines) / 20.0)
    }

    /// Composite resistance to pathogens, 0...1.
    public var diseaseResistance: Double {
        0.6 * geneticDiversity + 0.4 * hygienicBehaviour
    }

    /// A colony that never mated properly is a drone layer and is doomed.
    public var isProperlyMated: Bool { patrilines >= 4 }

    /// Rolls the genetics of a queen returning from a mating flight. The number
    /// of drones she meets depends on how well the flight went, which is
    /// weather-dependent in `MatingFlightSystem`.
    public static func fromMatingFlight(
        droneEncounters: Int,
        maternal: QueenGenetics,
        rng: inout SeededRandom
    ) -> QueenGenetics {
        /// Traits regress toward the mean of the drone population, with the
        /// maternal line pulling proportionally to how few drones she met.
        func inherit(_ maternalValue: Double) -> Double {
            let droneContribution = 0.35 + rng.unitValue() * 0.4
            let maternalWeight = 0.5
            let blended = maternalValue * maternalWeight + droneContribution * (1 - maternalWeight)
            let mutation = (rng.unitValue() - 0.5) * 0.12
            return min(1.0, max(0.0, blended + mutation))
        }

        return QueenGenetics(
            patrilines: droneEncounters,
            hygienicBehaviour: inherit(maternal.hygienicBehaviour),
            defensiveness: inherit(maternal.defensiveness),
            fecundity: min(1.4, max(0.5, maternal.fecundity + (rng.unitValue() - 0.45) * 0.3)),
            swarminess: inherit(maternal.swarminess),
            thriftiness: inherit(maternal.thriftiness)
        )
    }
}
