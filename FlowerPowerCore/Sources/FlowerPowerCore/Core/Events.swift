//
//  Events.swift
//  FlowerPowerCore
//
//  Systems never talk to the UI directly. They emit events, which the
//  simulation aggregates into a report — so a three-day absence hands the
//  interface a summary rather than a hundred thousand individual notifications.
//

import Foundation

public enum DeathCause: String, Codable, CaseIterable, Sendable {
    case oldAge
    case starvation
    case chill
    case overheating
    case disease
    case predation
    case evicted
    case swarmed
    case stungIntruder

    public var displayName: String {
        switch self {
        case .oldAge: return "Old Age"
        case .starvation: return "Starvation"
        case .chill: return "Chilled Brood"
        case .overheating: return "Overheating"
        case .disease: return "Disease"
        case .predation: return "Predation"
        case .evicted: return "Evicted"
        case .swarmed: return "Left with Swarm"
        case .stungIntruder: return "Died Defending"
        }
    }
}

public enum SimEvent: Equatable, Sendable {

    // Population
    case emerged(BeeKind)
    case died(BeeKind, DeathCause)
    case eggsLaid(count: Int, kind: BeeKind)

    // Colony lifecycle
    case queenCellStarted(QueenCell.Purpose)
    case queenEmerged(quality: Double)
    case queenMated(patrilines: Int)
    case matingFlightFailed
    case queenLost
    case queenFailing
    case swarmed(beesLost: Int)
    case absconded(beesLost: Int)
    case supersededQueen
    case layingWorkersAppeared
    case colonyCollapsed

    // Economy
    case cellsBuilt(count: Int, type: CellType)
    case combLost(count: Int)
    case patchDepleted(EntityID)
    case patchOutOfBloom(EntityID)
    case nectarFlowBegan
    case dearth

    // Environment
    case weatherChanged(Sky)
    case groundedByWeather
    case overheating
    case chilling

    // Health
    case infectionDetected(Pathogen)
    case infectionCleared(Pathogen)
    case infectionCritical(Pathogen)

    // Defence
    case attacked(Predator)
    case attackRepelled(Predator)
    case raidSucceeded(Predator, storesLost: Double)
    /// A siege has begun and the player has until `resolvesOnDay` to answer.
    case threatBegan(Predator, resolvesOnDay: Int)
    case threatEnded(Predator)

    // Decisions and their consequences
    case swarmPreparing(departsOnDay: Int)
    case swarmAbandoned
    case postureAdopted(HivePosture)
    case entranceSealed(Bool)
    case honeyTaken(Double)
    /// Honey the player had banked was put back into the colony's stores.
    case fed(Double)
    /// The nest was given more room to draw comb into.
    case combAdded(cells: Int)
    /// The colony was divided deliberately, rather than swarming.
    case colonyDivided(beesLeft: Int)

    // Warnings the UI should surface promptly
    case starving
    case winterStoresLow(have: Double, need: Double)

    /// The colony did something for the first time. Emitted by
    /// `MilestoneSystem`, once per milestone per colony, for ever.
    case milestone(Milestone)
}

/// Aggregated outcome of a span of simulated time.
public struct CatchUpReport: Equatable, Sendable {

    public var ticksSimulated: Int = 0
    public var daysSimulated: Int = 0

    public var emerged: [BeeKind: Int] = [:]
    public var died: [DeathCause: Int] = [:]
    public var eggsLaid: Int = 0
    public var cellsBuilt: Int = 0
    public var combLost: Int = 0

    public var depletedPatches: [EntityID] = []
    public var newInfections: [Pathogen] = []
    public var criticalInfections: [Pathogen] = []
    public var attacks: [Predator] = []
    public var storesRaided: Double = 0

    public var swarmed = false
    public var absconded = false
    public var queenLost = false
    public var queenMated = false
    public var superseded = false
    public var layingWorkers = false
    public var collapsed = false
    public var starved = false
    public var groundedDays = 0

    /// Firsts the colony reached while the player was away, in the order they
    /// happened. Kept apart from `highlights`, which is capped: a badge earned
    /// during a busy fortnight should not be the thing the cap throws out.
    public var milestones: [Milestone] = []

    /// Kept in arrival order and capped, so the UI can show a readable
    /// timeline without unbounded growth.
    public private(set) var highlights: [SimEvent] = []
    /// The day of each highlight, in step with `highlights`.
    public private(set) var highlightDays: [Int] = []
    public static let highlightLimit = 60

    public init() {}

    public var isEmpty: Bool { ticksSimulated == 0 }

    public var totalDeaths: Int { died.values.reduce(0, +) }
    public var totalEmerged: Int { emerged.values.reduce(0, +) }
    public var netPopulationChange: Int { totalEmerged - totalDeaths }

    /// This report followed by a later one, as if the two absences had been
    /// one. For a report the player has not read yet when the next arrives.
    public func merging(_ later: CatchUpReport) -> CatchUpReport {
        var merged = self
        merged.ticksSimulated += later.ticksSimulated
        merged.daysSimulated += later.daysSimulated
        merged.emerged.merge(later.emerged, uniquingKeysWith: +)
        merged.died.merge(later.died, uniquingKeysWith: +)
        merged.eggsLaid += later.eggsLaid
        merged.cellsBuilt += later.cellsBuilt
        merged.combLost += later.combLost
        merged.depletedPatches += later.depletedPatches
        merged.newInfections += later.newInfections
        merged.criticalInfections += later.criticalInfections
        merged.attacks += later.attacks
        merged.storesRaided += later.storesRaided
        merged.swarmed = swarmed || later.swarmed
        merged.absconded = absconded || later.absconded
        merged.queenLost = queenLost || later.queenLost
        merged.queenMated = queenMated || later.queenMated
        merged.superseded = superseded || later.superseded
        merged.layingWorkers = layingWorkers || later.layingWorkers
        merged.collapsed = collapsed || later.collapsed
        merged.starved = starved || later.starved
        merged.groundedDays += later.groundedDays
        merged.milestones += later.milestones
        merged.highlights = Array((highlights + later.highlights).prefix(Self.highlightLimit))
        merged.highlightDays = Array((highlightDays + later.highlightDays).prefix(Self.highlightLimit))
        return merged
    }

    public mutating func record(_ event: SimEvent, day: Int = 0) {
        switch event {
        case .emerged(let kind):
            emerged[kind, default: 0] += 1
        case .died(_, let cause):
            died[cause, default: 0] += 1
        case .eggsLaid(let count, _):
            eggsLaid += count
        case .cellsBuilt(let count, _):
            cellsBuilt += count
        case .combLost(let count):
            combLost += count
        case .patchDepleted(let id):
            depletedPatches.append(id)
        case .infectionDetected(let pathogen):
            newInfections.append(pathogen)
        case .infectionCritical(let pathogen):
            criticalInfections.append(pathogen)
        case .attacked(let predator):
            attacks.append(predator)
        case .raidSucceeded(_, let lost):
            storesRaided += lost
        case .swarmed:
            swarmed = true
        case .absconded:
            absconded = true
        case .queenLost:
            queenLost = true
        case .queenMated:
            queenMated = true
        case .supersededQueen:
            superseded = true
        case .layingWorkersAppeared:
            layingWorkers = true
        case .colonyCollapsed:
            collapsed = true
        case .starving:
            starved = true
        case .groundedByWeather:
            groundedDays += 1
        case .milestone(let milestone):
            milestones.append(milestone)
        default:
            break
        }

        guard event.isHighlight else { return }

        // Said again each day it stays true. Only the latest figure is news,
        // and three in a row buried everything between them.
        if case .winterStoresLow = event,
           let earlier = highlights.lastIndex(where: {
               if case .winterStoresLow = $0 { return true }
               return false
           }) {
            highlights.remove(at: earlier)
            highlightDays.remove(at: earlier)
        }

        guard highlights.count < Self.highlightLimit else { return }
        highlights.append(event)
        highlightDays.append(day)
    }
}

extension SimEvent {

    /// Whether this event is worth showing the player individually, rather than
    /// only counting. Births and deaths happen constantly; a swarm does not.
    public var isHighlight: Bool {
        switch self {
        // Weather included: it turns every day or two, so an 82-day absence read
        // as a forecast with a wasp somewhere in the middle of it.
        case .emerged, .died, .eggsLaid, .cellsBuilt, .overheating, .chilling,
             .starving, .patchDepleted, .groundedByWeather, .weatherChanged:
            return false
        // A flower going out of season is the calendar doing what it does,
        // and the garden already shows it on the flower. The first player to
        // open the app after a week away said it was the only thing the
        // report told them.
        case .patchOutOfBloom:
            return false
        case .queenCellStarted, .queenEmerged, .queenMated, .matingFlightFailed,
             .queenLost, .queenFailing, .swarmed, .absconded, .supersededQueen,
             .layingWorkersAppeared, .colonyCollapsed, .combLost,
             .nectarFlowBegan, .dearth,
             .infectionDetected, .infectionCleared, .infectionCritical,
             .attacked, .attackRepelled, .raidSucceeded, .winterStoresLow,
             .threatBegan, .threatEnded, .swarmPreparing, .swarmAbandoned,
             .postureAdopted, .entranceSealed, .honeyTaken, .fed,
             .combAdded, .colonyDivided, .milestone:
            return true
        }
    }

    /// Severity, for sorting and for deciding what deserves a notification on
    /// the watch.
    public var severity: Severity {
        switch self {
        case .colonyCollapsed, .absconded, .queenLost, .layingWorkersAppeared,
             .infectionCritical, .raidSucceeded:
            return .critical
        case .swarmed, .queenFailing, .matingFlightFailed, .infectionDetected,
             .attacked, .winterStoresLow, .dearth, .combLost,
             .threatBegan, .swarmPreparing:
            return .warning
        case .colonyDivided:
            // A division the player asked for is news, not a warning. They
            // know: they did it.
            return .notable
        case .milestone:
            // Informational, and deliberately never higher. A badge must not
            // be able to outrank the sentence saying the queen is lost, and
            // `.notable` is the tier `Symbols.swift` draws as an info circle.
            return .notable
        case .fed:
            // Taking surplus honey is routine — it is what a good year is
            // for. Giving it back is not: it only ever happens to a colony
            // that is short, and in a hard winter it is the difference
            // between seeing spring and not. Worth a line in the report.
            return .notable
        case .queenEmerged, .queenMated, .supersededQueen, .nectarFlowBegan,
             .infectionCleared, .attackRepelled, .queenCellStarted:
            return .notable
        default:
            return .routine
        }
    }

    public enum Severity: Int, Codable, Comparable, Sendable, CaseIterable {
        case routine
        case notable
        case warning
        case critical

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
