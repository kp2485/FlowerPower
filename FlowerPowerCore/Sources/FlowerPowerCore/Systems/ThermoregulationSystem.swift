//
//  ThermoregulationSystem.swift
//  FlowerPowerCore
//
//  A honey bee colony is a warm-blooded superorganism. It holds the brood nest
//  at 34-35C against anything the weather does, by shivering its flight muscles
//  to heat and by fanning evaporating water to cool. Both cost honey, and in
//  winter that cost is the single largest draw on the stores — which is why a
//  colony in a badly insulated cavity starves in February with comb still in
//  the hive.
//
//  The previous engine only ever cooled, so the nest drifted to ambient and the
//  brood chilled to death in spring.
//

import Foundation

public struct ThermoregulationSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        let target = targetTemperature(world, context)

        applyPassiveDrift(&world, context)
        applyMetabolicHeat(&world, &context, target: target)
        applyActiveCooling(&world, &context, target: target)
        regulateHumidity(&world, context)
        damageBroodIfOutOfBand(&world, &context, target: target)
    }

    /// A broodless winter cluster runs far cooler than a brood nest, because
    /// bees only pay for 35C when there is brood to keep alive.
    ///
    /// The subtlety is that a colony *about* to rear brood warms the nest
    /// first — real colonies begin warming in late winter, weeks before the
    /// queen lays. Without that, a colony that goes briefly broodless cools to
    /// the cluster temperature, the queen cannot lay into a cold nest, and it
    /// is deadlocked out of ever rearing brood again. That deadlock killed
    /// every test colony by day 60.
    private func targetTemperature(_ world: World, _ context: TickContext) -> Double {
        if world.hive.broodCount > 0 { return context.config.targetTemperature }

        guard world.hive.hasLayingQueen else {
            return context.config.broodlessClusterTemperature
        }
        guard world.hive.resources.edibleEnergy >= context.config.layingEnergyThreshold else {
            return context.config.broodlessClusterTemperature
        }

        // Colonies stay clustered through the depth of winter, then warm up
        // ahead of the spring build-up.
        // The nest must be warm before the queen will lay into it, so warming
        // has to start slightly ahead of the late-winter build-up.
        if context.season == .winter,
           Season.progress(context.day) < context.config.winterBuildUpStart - 0.05 {
            return context.config.broodlessClusterTemperature
        }

        return context.config.targetTemperature
    }

    /// Heat leaks toward ambient at a rate set by the cavity and the propolis
    /// envelope sealing its draughts.
    private func applyPassiveDrift(_ world: inout World, _ context: TickContext) {
        let ambient = world.weather.temperatureCelsius
        let insulation = min(
            0.97,
            world.hive.location.type.insulation + 0.08 * world.hive.propolisEnvelope
        )

        let leak = (ambient - world.hive.temperatureCelsius) * (1 - insulation) * context.config.thermalLeakRate
        world.hive.temperatureCelsius += leak
    }

    /// Bees decouple their wing muscles and shiver. It is effective and
    /// expensive: the honey burned here is what empties the stores by March.
    private func applyMetabolicHeat(
        _ world: inout World,
        _ context: inout TickContext,
        target: Double
    ) {
        let deficit = target - world.hive.temperatureCelsius
        guard deficit > 0 else { return }

        let adults = Double(world.hive.adultCount)
        guard adults > 0 else { return }

        // A cluster's heating power scales with the bees available to shiver,
        // and thrifty genetics make the cluster tighter and more efficient.
        let thrift = 1.0 + 0.4 * world.hive.genetics.thriftiness
        let maximumHeating = adults * context.config.heatingPerAdult * thrift
        let wanted = min(deficit, maximumHeating)

        // Shivering is fuelled by honey. If there is none, the colony cannot
        // hold temperature no matter how many bees it has — this is precisely
        // how colonies die in winter.
        let fuelNeeded = wanted * adults * context.config.honeyPerDegreeHeating
        let fuelAvailable = world.hive.resources.drain(fuelNeeded, of: .honey)

        let achieved = fuelNeeded > 0 ? wanted * (fuelAvailable / fuelNeeded) : 0
        world.hive.temperatureCelsius += achieved

        if fuelAvailable < fuelNeeded * 0.5 && deficit > context.config.safeTemperatureBand {
            context.emit(.starving)
        }
    }

    /// Fanners move air; water carriers supply the evaporative load. Together
    /// they are a working air conditioner, but only if there is water.
    private func applyActiveCooling(
        _ world: inout World,
        _ context: inout TickContext,
        target: Double
    ) {
        let excess = world.hive.temperatureCelsius - target
        guard excess > 0 else { return }

        let fanners = world.hive.workforce(for: .fanning)
        guard fanners > 0 else { return }

        // Dry fanning alone shifts little heat; evaporating water shifts a lot.
        let airflowCooling = fanners * context.config.coolingPerFanner
        let waterWanted = min(excess, airflowCooling * 2) * context.config.waterPerDegreeCooling
        let waterUsed = world.hive.resources.drain(waterWanted, of: .water)

        let evaporativeCooling = waterUsed / max(context.config.waterPerDegreeCooling, 1e-9)
        let achieved = min(excess, airflowCooling + evaporativeCooling)

        world.hive.temperatureCelsius -= achieved
    }

    /// Bees hold nest humidity near 60%. Too dry and eggs desiccate; too damp
    /// and chalkbrood takes hold — which `DiseaseSystem` reads off this value.
    private func regulateHumidity(_ world: inout World, _ context: TickContext) {
        let ambient = world.weather.humidity
        let drift = (ambient - world.hive.humidity) * 0.08
        world.hive.humidity += drift

        // Fanners actively drive the nest back toward the ideal.
        let fanners = world.hive.workforce(for: .fanning)
        guard fanners > 0 else { return }

        let correction = (context.config.targetHumidity - world.hive.humidity)
        let power = min(1.0, fanners / 30.0) * 0.15
        world.hive.humidity += correction * power
        world.hive.humidity = min(1, max(0, world.hive.humidity))
    }

    /// Brood is far less tolerant than adults. A few degrees off for a few
    /// hours produces chilled or overheated brood, and stunted survivors.
    private func damageBroodIfOutOfBand(
        _ world: inout World,
        _ context: inout TickContext,
        target: Double
    ) {
        guard world.hive.broodCount > 0 else { return }

        let deviation = abs(world.hive.temperatureCelsius - target)
        guard deviation > context.config.safeTemperatureBand else { return }

        let tooHot = world.hive.temperatureCelsius > target
        context.emit(tooHot ? .overheating : .chilling)

        let severity = (deviation - context.config.safeTemperatureBand)

        // Survivors of a thermal excursion emerge damaged even when they live.
        let damage = severity * context.config.broodDamagePerDegree
        for index in world.hive.bees.indices where world.hive.bees[index].isBrood {
            world.hive.bees[index].damage(damage)
        }

        let lossRate = severity * context.config.broodLossPerDegree
        BroodMortality.cull(
            &world,
            &context,
            fraction: lossRate,
            cause: tooHot ? .overheating : .chill
        )
    }
}

/// Shared helper for the several systems that kill brood, so the selection
/// rule — youngest and weakest first, as a real colony sacrifices — lives in
/// one place.
public enum BroodMortality {

    public static func cull(
        _ world: inout World,
        _ context: inout TickContext,
        fraction: Double,
        cause: DeathCause
    ) {
        guard fraction > 0 else { return }

        let broodIndices = world.hive.bees.indices.filter { world.hive.bees[$0].isBrood }
        guard !broodIndices.isEmpty else { return }

        var toKill = Int((Double(broodIndices.count) * fraction).rounded(.down))
        // Sub-integer losses still bite, probabilistically, so a small colony
        // is not simply immune to a bad night.
        if toKill == 0, context.rng.chance(Double(broodIndices.count) * fraction) {
            toKill = 1
        }
        guard toKill > 0 else { return }

        // The colony abandons its weakest brood first.
        let doomed = broodIndices
            .sorted { world.hive.bees[$0].vitality < world.hive.bees[$1].vitality }
            .prefix(toKill)
        let doomedSet = Set(doomed)

        for index in doomedSet {
            context.emit(.died(world.hive.bees[index].kind, cause))
        }

        world.hive.bees = world.hive.bees.enumerated()
            .filter { !doomedSet.contains($0.offset) }
            .map(\.element)
    }

    /// Kills adults, weakest first, and reports how many actually died.
    @discardableResult
    public static func cullAdults(
        _ world: inout World,
        _ context: inout TickContext,
        count: Int,
        cause: DeathCause,
        excludeQueen: Bool = true
    ) -> Int {
        guard count > 0 else { return 0 }

        let candidates = world.hive.bees.indices.filter { index in
            let bee = world.hive.bees[index]
            guard bee.isAdult else { return false }
            return !(excludeQueen && bee.kind == .queen)
        }
        guard !candidates.isEmpty else { return 0 }

        let doomed = candidates
            .sorted { world.hive.bees[$0].vitality < world.hive.bees[$1].vitality }
            .prefix(min(count, candidates.count))
        let doomedSet = Set(doomed)

        for index in doomedSet {
            let bee = world.hive.bees[index]
            context.emit(.died(bee.kind, cause))

            // Losing the queen is a colony-level event, not just one more
            // death, and it must be reported wherever it happens. Reporting it
            // only from `BroodSystem` meant a queen killed by a predator or by
            // disease vanished silently — the colony was doomed and nothing in
            // the log said so.
            if bee.kind == .queen {
                context.emit(.queenLost)
            }
        }

        world.hive.bees = world.hive.bees.enumerated()
            .filter { !doomedSet.contains($0.offset) }
            .map(\.element)

        return doomedSet.count
    }
}
