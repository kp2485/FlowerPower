//
//  World.swift
//  FlowerPowerCore
//
//  All mutable simulation state in one place. Systems read and write this and
//  nothing else, which is what keeps them independently testable.
//

import Foundation

public struct World: Codable, Equatable, Sendable {

    public var hive: Hive
    public var patches: [FlowerPatch]
    public var weather: Weather

    /// Recent attacks, newest last. Trimmed so save files do not grow forever.
    public var attackHistory: [AttackRecord]

    /// Rolling record of *completed* days' nectar intake, used to detect a flow
    /// or a dearth — the colony behaves very differently under each.
    public var recentNectarIntake: [Double]

    /// Nectar gathered so far today, folded into the window at the day boundary.
    public var todayNectarIntake: Double

    public init(
        hive: Hive,
        patches: [FlowerPatch] = [],
        weather: Weather = Weather(),
        attackHistory: [AttackRecord] = [],
        recentNectarIntake: [Double] = [],
        todayNectarIntake: Double = 0
    ) {
        self.hive = hive
        self.patches = patches
        self.weather = weather
        self.attackHistory = attackHistory
        self.recentNectarIntake = recentNectarIntake
        self.todayNectarIntake = todayNectarIntake
    }

    public static let attackHistoryLimit = 40
    public static let intakeWindow = 7

    /// Mean daily nectar intake over the recent window.
    public var averageNectarIntake: Double {
        guard !recentNectarIntake.isEmpty else { return 0 }
        return recentNectarIntake.reduce(0, +) / Double(recentNectarIntake.count)
    }

    /// A nectar flow: forage arriving faster than the colony consumes it. Real
    /// colonies switch behaviour wholesale — building comb, rearing brood and,
    /// if crowded, preparing to swarm.
    public var isInFlow: Bool {
        averageNectarIntake > Double(hive.adultCount) * Self.flowThresholdPerBee
    }

    /// Daily nectar per adult above which the colony treats conditions as a
    /// flow: it draws comb, rears brood hard, and starts thinking about
    /// swarming.
    public static let flowThresholdPerBee = 0.20

    /// A dearth. Colonies stop rearing brood, evict drones and start robbing.
    public var isInDearth: Bool {
        averageNectarIntake < Double(hive.adultCount) * Self.dearthThresholdPerBee
    }

    /// Below this the colony is in dearth: brood rearing stops, drones are
    /// evicted, and robbing begins.
    public static let dearthThresholdPerBee = 0.04

    /// Patches actually worth flying to right now.
    public func availablePatches(
        during season: Season,
        onDay day: Int,
        config: SimulationConfig
    ) -> [FlowerPatch] {
        patches.filter {
            $0.isInBloom(during: season)
                && $0.isWithinRange
                && !$0.isDepleted
                && !$0.hasFaded(onDay: day, config: config)
        }
    }

    /// Closes the books on the day just ended and starts a fresh tally.
    mutating func rollOverNectarIntake() {
        recentNectarIntake.append(todayNectarIntake)
        todayNectarIntake = 0
        if recentNectarIntake.count > Self.intakeWindow {
            recentNectarIntake.removeFirst(recentNectarIntake.count - Self.intakeWindow)
        }
    }

    mutating func recordAttack(_ record: AttackRecord) {
        attackHistory.append(record)
        if attackHistory.count > Self.attackHistoryLimit {
            attackHistory.removeFirst(attackHistory.count - Self.attackHistoryLimit)
        }
    }
}
