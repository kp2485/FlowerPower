//
//  Threats.swift
//  FlowerPowerCore
//
//  Features.md lists twenty-odd creatures that attack hives. They are not
//  interchangeable: a bear ends the colony in one night, wax moths only take
//  hold once the colony is too weak to patrol its own comb, and a crab spider
//  never touches the hive at all — it eats foragers out at the flowers.
//  Modelling *how* each one attacks is what makes defence a real decision.
//

import Foundation

public enum AttackStyle: String, Codable, Sendable {
    /// Forces the entrance. Guards can meet it head on.
    case entrance
    /// Picks off foragers in the field, where guards cannot help.
    case field
    /// Eats the comb itself, and only gets a foothold in a weak colony.
    case comb
    /// Steals stores without much fighting.
    case pilfer
    /// Destroys the nest outright.
    case catastrophic
    /// Lives inside the colony and weakens it over time.
    case parasite

    public var displayName: String {
        switch self {
        case .entrance: return "Entrance Assault"
        case .field: return "Field Ambush"
        case .comb: return "Comb Infestation"
        case .pilfer: return "Pilfering"
        case .catastrophic: return "Nest Destruction"
        case .parasite: return "Parasitism"
        }
    }
}

public extension AttackStyle {

    /// What the colony is actually facing, and what can be done about it.
    ///
    /// The text a decision card shows beside the postures. Here rather than in
    /// the view because it is an exhaustive switch over an engine type — see
    /// `Symbols.swift` — and because the two styles with no decision to offer
    /// should say so in one place.
    var explanation: String {
        switch self {
        case .entrance:
            return "They are trying to force the door. Guards can meet them head on, or the bees can narrow the entrance to a slot they cannot get through."
        case .pilfer:
            return "A raider at the entrance, night after night. A narrowed entrance keeps it out; guards can meet it but will die stinging."
        case .field:
            return "It is picking foragers off at the flowers, where guards cannot help. The only defence is not to send them."
        case .comb:
            return "Larvae in the comb, eating it. Cleaners can hunt them down, at the cost of everything else the cleaners would be doing."
        case .catastrophic:
            return "There is nothing to be done about this one. It will take what it takes and leave."
        case .parasite:
            return "This one is already inside, and lives there. No posture reaches it."
        }
    }

    /// Whether there is a posture worth offering against it.
    var hasAnswer: Bool { !HivePosture.options(against: self).isEmpty }
}

public enum Predator: String, Codable, CaseIterable, Sendable {

    // Mammals
    case bear
    case badger
    case skunk
    case raccoon
    case opossum
    case mouse
    case human

    // Birds
    case beeEater
    case honeyBuzzard
    case woodpecker
    case shrike

    // Insects and arachnids
    case wasp
    case hornet
    case robberBee
    case ant
    case waxMoth
    case hiveBeetle
    case crabSpider
    case prayingMantis
    case dragonfly

    // Reptiles
    case toad

    public var displayName: String {
        switch self {
        case .bear: return "Bear"
        case .badger: return "Honey Badger"
        case .skunk: return "Skunk"
        case .raccoon: return "Raccoon"
        case .opossum: return "Opossum"
        case .mouse: return "Mouse"
        case .human: return "Human"
        case .beeEater: return "Bee Eater"
        case .honeyBuzzard: return "Honey Buzzard"
        case .woodpecker: return "Woodpecker"
        case .shrike: return "Shrike"
        case .wasp: return "Wasp"
        case .hornet: return "Hornet"
        case .robberBee: return "Robber Bees"
        case .ant: return "Ants"
        case .waxMoth: return "Wax Moths"
        case .hiveBeetle: return "Hive Beetles"
        case .crabSpider: return "Crab Spider"
        case .prayingMantis: return "Praying Mantis"
        case .dragonfly: return "Dragonfly"
        case .toad: return "Toad"
        }
    }

    public var attackStyle: AttackStyle {
        switch self {
        case .bear, .badger, .human: return .catastrophic
        case .skunk, .raccoon, .opossum, .toad: return .entrance
        case .mouse: return .comb
        case .beeEater, .honeyBuzzard, .shrike, .crabSpider,
             .prayingMantis, .dragonfly: return .field
        case .woodpecker: return .entrance
        case .wasp, .hornet, .robberBee: return .entrance
        case .ant: return .pilfer
        case .waxMoth, .hiveBeetle: return .comb
        }
    }

    /// Seasons in which this predator is a live threat.
    public var activeSeasons: Set<Season> {
        switch self {
        case .bear, .badger: return [.spring, .summer, .autumn]
        case .mouse: return [.autumn, .winter]
        case .wasp, .hornet, .robberBee: return [.summer, .autumn]
        case .waxMoth, .hiveBeetle: return [.summer, .autumn]
        case .beeEater, .honeyBuzzard, .shrike: return [.spring, .summer]
        case .crabSpider, .prayingMantis, .dragonfly: return [.summer, .autumn]
        case .ant: return [.spring, .summer, .autumn]
        case .toad: return [.spring, .summer]
        case .skunk, .raccoon, .opossum, .woodpecker: return [.autumn, .winter, .spring]
        case .human: return [.summer, .autumn]
        }
    }

    /// Baseline chance per day of an encounter, before site and season.
    public var dailyEncounterChance: Double {
        switch self {
        // Deliberately rare. These three cannot be repelled and typically end
        // the colony, so their combined rate is kept near one chance in seven
        // per year rather than one in two.
        case .bear: return 0.00020
        case .badger: return 0.00012
        case .human: return 0.00025
        case .skunk: return 0.010
        case .raccoon: return 0.008
        case .opossum: return 0.006
        case .mouse: return 0.014
        case .woodpecker: return 0.007
        case .beeEater: return 0.012
        case .honeyBuzzard: return 0.004
        case .shrike: return 0.007
        case .wasp: return 0.035
        case .hornet: return 0.012
        case .robberBee: return 0.020
        case .ant: return 0.028
        case .waxMoth: return 0.018
        case .hiveBeetle: return 0.012
        case .crabSpider: return 0.030
        case .prayingMantis: return 0.014
        case .dragonfly: return 0.020
        case .toad: return 0.010
        }
    }

    /// How hard this attacker is to repel, 0...1. Guards can see off a wasp;
    /// nothing a colony can do stops a bear.
    public var threatLevel: Double {
        switch self {
        case .bear, .badger, .human: return 1.0
        case .skunk, .raccoon, .opossum: return 0.55
        case .woodpecker: return 0.45
        case .mouse: return 0.40
        case .hornet: return 0.70
        case .wasp: return 0.35
        case .robberBee: return 0.60
        case .ant: return 0.30
        case .waxMoth, .hiveBeetle: return 0.50
        case .beeEater, .honeyBuzzard, .shrike: return 0.65
        case .crabSpider, .prayingMantis, .dragonfly, .toad: return 0.25
        }
    }

    /// Bees killed in a successful attack, as a fraction of the adult
    /// population.
    public var beeLossFraction: ClosedRange<Double> {
        switch self {
        case .bear, .badger, .human: return 0.45...0.85
        case .skunk, .raccoon, .opossum, .toad: return 0.02...0.06
        case .woodpecker: return 0.01...0.03
        case .mouse: return 0.01...0.04
        case .hornet: return 0.05...0.15
        case .wasp: return 0.01...0.05
        case .robberBee: return 0.03...0.09
        case .beeEater, .honeyBuzzard, .shrike: return 0.02...0.07
        case .crabSpider, .prayingMantis, .dragonfly: return 0.005...0.02
        case .ant, .waxMoth, .hiveBeetle: return 0.0...0.01
        }
    }

    /// Fraction of stores taken in a successful attack.
    public var storesLossFraction: ClosedRange<Double> {
        switch self {
        case .bear, .badger, .human: return 0.6...1.0
        case .robberBee: return 0.15...0.45
        case .ant: return 0.02...0.08
        case .hiveBeetle: return 0.05...0.20
        case .skunk, .raccoon, .opossum: return 0.0...0.05
        case .mouse: return 0.03...0.10
        default: return 0.0...0.0
        }
    }

    /// Comb cells destroyed in a successful attack.
    public var combLossFraction: ClosedRange<Double> {
        switch self {
        case .bear, .badger, .human: return 0.5...0.9
        case .mouse: return 0.05...0.18
        case .waxMoth: return 0.10...0.30
        case .woodpecker: return 0.01...0.05
        default: return 0.0...0.0
        }
    }

    /// Whether guard bees can meaningfully contest this attacker.
    public var isDeterredByGuards: Bool {
        switch attackStyle {
        case .entrance, .pilfer: return true
        case .comb: return true          // patrolled comb resists moths and beetles
        case .field, .catastrophic: return false
        case .parasite: return false
        }
    }

    /// Some attackers only get in when the colony is already weak. Wax moths
    /// and beetles are symptoms of collapse as much as causes of it.
    public var exploitsWeakColonies: Bool {
        switch self {
        case .waxMoth, .hiveBeetle, .mouse, .robberBee, .ant: return true
        default: return false
        }
    }

    public var isNocturnal: Bool {
        switch self {
        case .skunk, .raccoon, .opossum, .mouse, .waxMoth, .toad: return true
        default: return false
        }
    }
}

/// A resolved attack, retained briefly so the UI can narrate it.
public struct AttackRecord: Identifiable, Codable, Equatable, Sendable {

    public let id: EntityID
    public let predator: Predator
    public let day: Int
    public let wasRepelled: Bool
    public let beesLost: Int
    public let storesLost: Double
    public let combLost: Int

    public init(
        id: EntityID,
        predator: Predator,
        day: Int,
        wasRepelled: Bool,
        beesLost: Int,
        storesLost: Double,
        combLost: Int
    ) {
        self.id = id
        self.predator = predator
        self.day = day
        self.wasRepelled = wasRepelled
        self.beesLost = beesLost
        self.storesLost = storesLost
        self.combLost = combLost
    }
}
