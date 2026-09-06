//
//  Posture.swift
//  FlowerPowerCore
//
//  The colony's stance, and the events that ask the player to choose one.
//
//  Almost everything a colony does, it does by instinct, and the engine
//  already models that. A posture is the one place the player can lean on it:
//  for a few days the colony holds the entrance, or seals it, or keeps its
//  foragers home, or turns its cleaners out. Each costs something — usually
//  forage — and each helps against some threats and not others.
//
//  The rules that keep this an idle game rather than a pager:
//
//  - **Instinct is the default.** With no posture chosen, the colony behaves
//    exactly as it did before postures existed. Not responding costs nothing
//    that instinct would not have cost anyway.
//  - **Windows are real.** A threat opens a window as long as the siege
//    actually lasts in simulated time; a swarm gives the days between the
//    first swarm cell and departure. At two real hours per simulated day,
//    that is half an hour to most of a day. Nothing needs answering in
//    seconds.
//  - **Never retroactive.** A posture applies from the tick it is adopted.
//    Catch-up stays deterministic; player choices are inputs with times.
//

import Foundation

// MARK: - Posture

public enum HivePosture: String, Codable, CaseIterable, Sendable {

    /// Do what a colony does. The default, and what happens when nobody
    /// answers.
    case instinct

    /// Every bee that can sting is at the entrance. Strong against anything
    /// that comes to the door; costs foragers, and defenders die doing it.
    case holdEntrance

    /// Propolis narrows the entrance to a slot. Hard to force, hard to rob,
    /// mouse-proof — and slower to fly through, so foraging suffers while it
    /// stands.
    case narrowEntrance

    /// Foragers stay in. Nothing for a bee-eater or a crab spider to take,
    /// and nothing coming in either.
    case foragersHome

    /// Cleaners and mortuary bees turned out in force against wax moth and
    /// beetle larvae in the comb.
    case cleanersOut

    /// Builders drawing comb and foragers held back, to relieve the
    /// congestion that drives swarming. Reduces the chance; does not remove
    /// it, which is about what a beekeeper achieves by giving room.
    case makeRoom

    public var displayName: String {
        switch self {
        case .instinct: return "Instinct"
        case .holdEntrance: return "Hold the Entrance"
        case .narrowEntrance: return "Narrow the Entrance"
        case .foragersHome: return "Keep the Foragers Home"
        case .cleanersOut: return "Send in the Cleaners"
        case .makeRoom: return "Make Room"
        }
    }

    public var detail: String {
        switch self {
        case .instinct:
            return "The colony does what a colony does."
        case .holdEntrance:
            return "Every bee that can sting meets the attacker at the door. Fewer foragers out, and defenders die doing it."
        case .narrowEntrance:
            return "Propolis narrows the entrance to a slot. Hard to force, hard to rob, slow to fly through."
        case .foragersHome:
            return "Nobody goes out. Nothing for an ambusher to take, and nothing coming in."
        case .cleanersOut:
            return "Cleaners hunt the comb for moth and beetle larvae, at the expense of everything else."
        case .makeRoom:
            return "Builders draw comb and foragers hold back, to ease the crowding that sends a swarm out."
        }
    }

    /// What the posture costs in foraging while it stands.
    public var forageMultiplier: Double {
        switch self {
        case .instinct: return 1.0
        case .holdEntrance: return 0.7
        case .narrowEntrance: return 0.8
        case .foragersHome: return 0.1
        case .cleanersOut: return 0.9
        case .makeRoom: return 0.85
        }
    }

    /// How much better the colony defends the entrance in this posture.
    public func defenceMultiplier(against style: AttackStyle) -> Double {
        switch (self, style) {
        case (.holdEntrance, .entrance), (.holdEntrance, .pilfer): return 1.6
        case (.narrowEntrance, .entrance), (.narrowEntrance, .pilfer): return 1.4
        default: return 1.0
        }
    }

    /// Losses in the field, scaled. Only keeping the foragers home helps, and
    /// it helps a great deal.
    public func fieldLossMultiplier() -> Double {
        self == .foragersHome ? 0.15 : 1.0
    }

    public func combLossMultiplier() -> Double {
        self == .cleanersOut ? 0.3 : 1.0
    }

    /// Defenders die stinging. Turning the whole colony out means more of
    /// them do.
    public func casualtyMultiplier() -> Double {
        self == .holdEntrance ? 1.3 : 1.0
    }

    /// The postures worth offering against a given attack style. Everything
    /// else is noise on the decision.
    public static func options(against style: AttackStyle) -> [HivePosture] {
        switch style {
        case .entrance: return [.holdEntrance, .narrowEntrance, .instinct]
        case .pilfer: return [.narrowEntrance, .holdEntrance, .instinct]
        case .field: return [.foragersHome, .instinct]
        case .comb: return [.cleanersOut, .instinct]
        case .catastrophic, .parasite: return []
        }
    }
}

// MARK: - A threat with a window

public struct ActiveThreat: Codable, Equatable, Sendable {

    public let predator: Predator
    public let beganOnDay: Int
    /// The day the siege resolves, with whatever posture the colony holds
    /// then. Until that day the player can still answer.
    public let resolvesOnDay: Int

    public init(predator: Predator, beganOnDay: Int, resolvesOnDay: Int) {
        self.predator = predator
        self.beganOnDay = beganOnDay
        self.resolvesOnDay = resolvesOnDay
    }

    public var style: AttackStyle { predator.attackStyle }
    public var options: [HivePosture] { HivePosture.options(against: style) }

    public func daysRemaining(on day: Int) -> Int {
        max(0, resolvesOnDay - day)
    }
}

extension Predator {

    /// How long an attack of this kind goes on before it is decided. A wasp
    /// siege lasts days; a bear is over in a night and there is nothing to
    /// decide, so it has no window at all.
    public var siegeDays: Int {
        switch attackStyle {
        case .entrance: return 2
        case .pilfer: return 3
        case .field: return 1
        case .comb: return 4
        case .catastrophic, .parasite: return 0
        }
    }

    public var hasDecisionWindow: Bool { siegeDays > 0 }
}

// MARK: - A swarm on its way

public struct PendingSwarm: Codable, Equatable, Sendable {

    public let startedOnDay: Int
    public let departsOnDay: Int
    /// Whether the player has tried to talk them out of it.
    public var discouraged: Bool

    public init(startedOnDay: Int, departsOnDay: Int, discouraged: Bool = false) {
        self.startedOnDay = startedOnDay
        self.departsOnDay = departsOnDay
        self.discouraged = discouraged
    }

    public func daysRemaining(on day: Int) -> Int {
        max(0, departsOnDay - day)
    }
}

/// What left. Kept so the player can choose to go with it.
public struct DepartedSwarm: Codable, Equatable, Sendable {

    public let day: Int
    public let queen: Bee
    public let workers: [Bee]
    public let genetics: QueenGenetics
    /// Honey the bees carried out in their crops.
    public let honeyCarried: Double
    /// The lineage record of the queen who left, so she keeps her number.
    public let queenNumber: Int?

    public init(
        day: Int,
        queen: Bee,
        workers: [Bee],
        genetics: QueenGenetics,
        honeyCarried: Double,
        queenNumber: Int?
    ) {
        self.day = day
        self.queen = queen
        self.workers = workers
        self.genetics = genetics
        self.honeyCarried = honeyCarried
        self.queenNumber = queenNumber
    }

    public var beeCount: Int { workers.count + 1 }
}
