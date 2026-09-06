//
//  BroodSystem.swift
//  FlowerPowerCore
//
//  Ageing, emergence and death. Runs once per simulated day.
//

import Foundation

public struct BroodSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        let hadQueen = world.hive.isQueenright

        ageEveryone(&world, &context)
        ageQueenCells(&world, &context)

        if hadQueen && !world.hive.isQueenright {
            context.emit(.queenLost)
            world.hive.daysQueenless = 0
        } else if !world.hive.isQueenright {
            world.hive.daysQueenless += 1
        } else {
            world.hive.daysQueenless = 0
        }

        evictDronesInDearth(&world, &context)
    }

    private func ageEveryone(_ world: inout World, _ context: inout TickContext) {
        var survivors: [Bee] = []
        survivors.reserveCapacity(world.hive.bees.count)
        let day = context.day

        for bee in world.hive.bees {
            var aging = bee

            switch aging.advanceOneDay(upgrade: world.hive.broodUpgrade, day: day) {
            case .aged:
                survivors.append(aging)

            case .advancedTo(let stage):
                if stage == .adult {
                    // A bee that emerges too damaged to fly never forages. This
                    // is deformed wing virus made concrete, and it is how a
                    // mite-heavy colony starves with a full nest of bees.
                    context.emit(.emerged(aging.kind))
                }
                survivors.append(aging)

            case .diedOfOldAge:
                context.emit(.died(aging.kind, .oldAge))
            }
        }

        world.hive.bees = survivors
    }

    private func ageQueenCells(_ world: inout World, _ context: inout TickContext) {
        for index in world.hive.comb.queenCells.indices {
            world.hive.comb.queenCells[index].advanceOneDay()
        }
    }

    /// Drones are a luxury. When the flow stops, workers drag them to the
    /// entrance and refuse to let them back in — a colony carrying drones into
    /// winter would not survive it.
    private func evictDronesInDearth(_ world: inout World, _ context: inout TickContext) {
        let season = context.season
        let shouldEvict = season == .autumn || season == .winter || world.isInDearth(context.config)
        guard shouldEvict else { return }

        // A queenless colony keeps its drones: they may yet be needed to mate a
        // replacement queen.
        guard world.hive.isQueenright else { return }

        var kept: [Bee] = []
        kept.reserveCapacity(world.hive.bees.count)

        for bee in world.hive.bees {
            let isEvictable = bee.kind == .drone && bee.isAdult
            if isEvictable, context.rng.chance(context.config.droneEvictionChance) {
                context.emit(.died(.drone, .evicted))
            } else {
                kept.append(bee)
            }
        }

        world.hive.bees = kept
    }
}
