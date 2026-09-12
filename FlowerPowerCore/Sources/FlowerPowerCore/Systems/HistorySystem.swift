//
//  HistorySystem.swift
//  FlowerPowerCore
//
//  Takes one reading of the colony a day, for the charts.
//
//  Last in the pipeline, after `LineageSystem`, and for the same reason: it
//  reads the finished state and writes a record nothing else looks at. It
//  draws nothing from the random stream and changes nothing but
//  `World.history`, which is what makes it safe to add to a balanced engine —
//  the same seed must still produce the same colony.
//

import Foundation

public struct HistorySystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        let hive = world.hive

        // A colony that has ended does not change, and the clock keeps
        // running: a player who leaves a dead colony alone for six months
        // would come back to a record holding six months of identical empty
        // days and none of the year that mattered. The end is written once,
        // so the charts run down to it, and then nothing more.
        if hive.isCollapsed, world.history.samples.last?.status == .collapsed { return }

        world.history.append(
            DailySample(
                day: context.day,
                adults: hive.adultCount,
                brood: hive.broodCount,
                workers: hive.count(kind: .worker),
                drones: hive.count(kind: .drone),
                winterBees: hive.bees.filter { $0.isAdult && $0.physiology == .winter }.count,
                edibleEnergy: hive.resources.edibleEnergy,
                winterRequirement: hive.winterStoresRequired,
                nestTemperature: hive.temperatureCelsius,
                outsideTemperature: world.weather.temperatureCelsius,
                combCells: hive.comb.builtCells,
                // `ForagingSystem` closes yesterday's tally at this same
                // boundary, earlier in the pipeline, so the last entry in the
                // window is the day that has just ended. On the very first
                // day of a colony there is no day behind it and the figure is
                // honestly zero.
                nectarIntake: world.recentNectarIntake.last ?? 0,
                alarm: hive.pheromones.alarm,
                status: ColonyStatus.evaluate(
                    hive: hive, season: context.season, config: context.config
                )
            )
        )
    }
}
