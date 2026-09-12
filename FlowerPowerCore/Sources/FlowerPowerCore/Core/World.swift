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

    /// Identifiers of flowers other people have sent, so the same one cannot
    /// be imported twice.
    ///
    /// Kept here rather than inferred from `patches` because a patch can be
    /// pruned or a colony started afresh, and neither of those should make an
    /// old share importable again — a shared flower arrives in a message that
    /// stays in the thread for ever and can be tapped any number of times.
    public var importedShares: Set<String> = []

    // MARK: Decisions

    /// The colony's stance, and how long it holds. See `HivePosture`.
    public var posture: HivePosture = .instinct
    public var postureUntilDay: Int?

    /// A siege in progress, during which the player may answer.
    public var activeThreat: ActiveThreat?

    /// A swarm on its way, during which the player may answer.
    public var pendingSwarm: PendingSwarm?

    /// The last swarm to leave, kept so the player may go with it.
    public var lastSwarm: DepartedSwarm?

    /// Whether the entrance is propolised down for winter.
    public var entranceSealed = false
    /// The player's word on it for this autumn, or nil for instinct.
    public var entranceDecision: Bool?

    // MARK: Record

    public var lineage = Lineage()
    public var almanac = Almanac()
    /// Honey the player has taken, over the life of the colony.
    public var honeyTaken: Double = 0
    /// What this colony has done for the first time. See `Milestones` for why
    /// they belong to the colony rather than to the player.
    public var milestones = Milestones()

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

    /// Decoded by hand for one reason: Swift's synthesised decoder ignores
    /// property defaults and throws on a missing key, so adding
    /// `importedShares` would have made every save written before sharing
    /// existed undecodable. `GameStore.load` treats an unreadable save as no
    /// save, so that would have silently deleted people's colonies.
    ///
    /// Only `init(from:)` is written out; the encoder is still synthesised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hive = try container.decode(Hive.self, forKey: .hive)
        patches = try container.decode([FlowerPatch].self, forKey: .patches)
        weather = try container.decode(Weather.self, forKey: .weather)
        attackHistory = try container.decode([AttackRecord].self, forKey: .attackHistory)
        recentNectarIntake = try container.decode([Double].self, forKey: .recentNectarIntake)
        todayNectarIntake = try container.decode(Double.self, forKey: .todayNectarIntake)
        importedShares = try container.decodeIfPresent(
            Set<String>.self, forKey: .importedShares
        ) ?? []

        // Everything below arrived with the decision and record features, and
        // every save from before then must still open.
        posture = try container.decodeIfPresent(HivePosture.self, forKey: .posture) ?? .instinct
        postureUntilDay = try container.decodeIfPresent(Int.self, forKey: .postureUntilDay)
        activeThreat = try container.decodeIfPresent(ActiveThreat.self, forKey: .activeThreat)
        pendingSwarm = try container.decodeIfPresent(PendingSwarm.self, forKey: .pendingSwarm)
        lastSwarm = try container.decodeIfPresent(DepartedSwarm.self, forKey: .lastSwarm)
        entranceSealed = try container.decodeIfPresent(Bool.self, forKey: .entranceSealed) ?? false
        entranceDecision = try container.decodeIfPresent(Bool.self, forKey: .entranceDecision)
        lineage = try container.decodeIfPresent(Lineage.self, forKey: .lineage) ?? Lineage()
        almanac = try container.decodeIfPresent(Almanac.self, forKey: .almanac) ?? Almanac()
        honeyTaken = try container.decodeIfPresent(Double.self, forKey: .honeyTaken) ?? 0
        milestones = try container.decodeIfPresent(
            Milestones.self, forKey: .milestones
        ) ?? Milestones()
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
    ///
    /// Both thresholds live in `SimulationConfig` because they are expressed
    /// in forage units, and those units were redefined when nectar became
    /// sugar yield derived from real floral traits.
    public func isInFlow(_ config: SimulationConfig) -> Bool {
        averageNectarIntake > Double(hive.adultCount) * config.flowThresholdPerBee
    }

    /// A dearth. Colonies stop rearing brood, evict drones and start robbing.
    public func isInDearth(_ config: SimulationConfig) -> Bool {
        averageNectarIntake < Double(hive.adultCount) * config.dearthThresholdPerBee
    }

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
