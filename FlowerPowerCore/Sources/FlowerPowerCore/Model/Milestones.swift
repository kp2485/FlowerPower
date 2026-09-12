//
//  Milestones.swift
//  FlowerPowerCore
//
//  The things a colony did once and will never do for the first time again.
//
//  An idle game lives on legacy, and this one was already generating it — the
//  first flower photographed, the first brood out of the comb, a queen home
//  from her mating flight, a wasp driven off at the entrance, a winter got
//  through — and then letting all of it go past unmarked. The `Lineage` keeps
//  who reigned and the `Almanac` keeps what happened on a given day; neither
//  of them says "this was the first time".
//
//  Two decisions worth stating, because both could reasonably have gone the
//  other way.
//
//  **Milestones belong to a colony, not to a player.** They live on `World`,
//  beside the lineage and the almanac, so a colony that dies takes its badges
//  with it and the next one earns its own. That is the same rule the rest of
//  the record follows, and it is the one that keeps the badges meaning
//  something: a page of permanent ticks accumulated across a dozen dead
//  colonies is a list of things the *player* has seen, which is a different
//  and much less interesting object. The garden is the exception the game
//  already makes — the flowers are photographs of real places and they carry
//  over — so the garden badges are re-earned on a new colony's first tick.
//  That is correct: those flowers really are in the new colony's garden.
//
//  **A milestone is a condition, not a hook.** Nothing that happens in the
//  game announces a milestone; `MilestoneSystem` looks at the finished world
//  and the tick's events and works out what became true. So a condition can be
//  added or a threshold moved without touching a single other system, and no
//  system has to know that milestones exist.
//

import Foundation

/// Something a colony did for the first time.
///
/// Every case has to be observable from `World`, the hive, or the events of a
/// single tick — see `MilestoneSystem`, which is the only thing that awards
/// them. Two candidates were dropped on exactly that test and it is worth
/// recording why, so nobody re-adds them and quietly ships a badge that can
/// never be earned:
///
/// - *Moved house and still alive a month later.* `Simulation.relocate` leaves
///   no dated trace in the world at all. It writes an almanac line, and the
///   line it writes is `.absconded`, indistinguishable from a colony that
///   absconded of its own accord. Awarding this needs a `relocatedOnDay` on
///   `World`, which is a change to the save format for one badge.
/// - *A full year, and two full years.* The colony's year begins in spring and
///   winter is the last season of it, so the first day of the second spring
///   and the colony's first anniversary are the same day — see
///   `Season.daysPerYear`. They would have been two badges for one moment, and
///   `firstWinterSurvived` is the better name for it.
public enum Milestone: String, Codable, CaseIterable, Sendable {

    // MARK: The garden

    case firstFlower
    case tenFlowers
    case placedToFamily
    case fiveFamilies
    case tenFamilies
    case gardenAllYear
    case firstSharedFlower

    // MARK: The nest

    case firstComb
    case firstBrood
    case hundredAdults
    case twoHundredAdults
    case fiveHundredAdults

    // MARK: The queens

    case firstQueenMated
    case supersedureSurvived
    case queenNamed

    // MARK: Dividing

    case firstSwarm
    case swarmTalkedOut
    case firstSplit

    // MARK: Stores and the winter

    case firstHoney
    case sealedForWinter
    case firstWinterSurvived
    case secondWinterSurvived

    // MARK: The entrance

    case firstRaidRepelled
    case tenRaidsRepelled

    /// The name on the badge.
    public var title: String {
        switch self {
        case .firstFlower: return "The First Flower"
        case .tenFlowers: return "Ten Flowers"
        case .placedToFamily: return "Placed to a Family"
        case .fiveFamilies: return "Five Families"
        case .tenFamilies: return "Ten Families"
        case .gardenAllYear: return "Something Out All Year"
        case .firstSharedFlower: return "A Flower from Someone Else"

        case .firstComb: return "The First Comb"
        case .firstBrood: return "The First Brood"
        case .hundredAdults: return "A Hundred Bees"
        case .twoHundredAdults: return "A Colony in Its Stride"
        case .fiveHundredAdults: return "Five Hundred Bees"

        case .firstQueenMated: return "Home from the Mating Flight"
        case .supersedureSurvived: return "Superseded and Still Standing"
        case .queenNamed: return "A Queen with a Name"

        case .firstSwarm: return "The First Swarm"
        case .swarmTalkedOut: return "Talked Out of It"
        case .firstSplit: return "Divided on Purpose"

        case .firstHoney: return "The First Honey"
        case .sealedForWinter: return "Sealed for Winter"
        case .firstWinterSurvived: return "Through the First Winter"
        case .secondWinterSurvived: return "Through the Second Winter"

        case .firstRaidRepelled: return "Driven Off at the Entrance"
        case .tenRaidsRepelled: return "Ten Times Driven Off"
        }
    }

    /// One sentence: what happened, and why a colony cares.
    public var detail: String {
        switch self {
        case .firstFlower:
            return "You photographed a real flower and it became forage — "
                + "everything the colony ever eats starts here."
        case .tenFlowers:
            return "Ten stands of flowers in the garden, which is enough that "
                + "one going over is no longer a famine."
        case .placedToFamily:
            return "A flower was placed to its family, and a family is enough "
                + "to know what the nectar in it is worth."
        case .fiveFamilies:
            return "Five plant families in the garden; a colony fed from five "
                + "families gets protein it cannot get from one."
        case .tenFamilies:
            return "Ten plant families, which is a landscape rather than a "
                + "flowerbed."
        case .gardenAllYear:
            return "You found a flower in every season, so there is something "
                + "for the bees to work whenever they can fly."
        case .firstSharedFlower:
            return "Somebody sent you a flower they had photographed, and your "
                + "bees are working it."

        case .firstComb:
            return "The bees drew their first comb — seven units of honey a "
                + "cell, and every cell is a cradle or a larder."
        case .firstBrood:
            return "The first bee reared in this nest chewed her way out; from "
                + "here the colony can replace what it loses."
        case .hundredAdults:
            return "A hundred adult bees. Enough to hold a nest temperature "
                + "and put real numbers in the field."
        case .twoHundredAdults:
            return "Two hundred adults, which is about as strong as a colony "
                + "gets in its founding year."
        case .fiveHundredAdults:
            return "Five hundred adults — an established colony, the kind that "
                + "makes a surplus and thinks about swarming."
        case .firstQueenMated:
            return "A virgin queen flew, found her drones and came home. Most "
                + "of what kills a colony in its second year is this going "
                + "wrong."
        case .supersedureSurvived:
            return "The bees replaced their own failing queen and her daughter "
                + "is laying — a colony renewing itself without a gap."
        case .queenNamed:
            return "You gave a queen a name, which is how a line of numbers "
                + "turns into a dynasty."

        case .firstSwarm:
            return "The colony sent out a swarm. It cost half the bees and it "
                + "is the only way a colony reproduces."
        case .swarmTalkedOut:
            return "The bees tore down their own queen cells and stayed. You "
                + "gave them a reason to."
        case .firstSplit:
            return "You divided the colony before it divided itself, and kept "
                + "the foragers where the honey is."

        case .firstHoney:
            return "You took honey the colony could spare. It is the only "
                + "thing in the game the bees make for you rather than for "
                + "themselves."
        case .sealedForWinter:
            return "The entrance was propolised down to a slot — warmer, "
                + "defensible, and the last job of the year."
        case .firstWinterSurvived:
            return "The cluster held to the first day of the second spring. "
                + "Most colonies that die, die here."
        case .secondWinterSurvived:
            return "A second winter through. A colony that has done this twice "
                + "has done everything a colony has to do."

        case .firstRaidRepelled:
            return "The guards turned something away at the entrance, and "
                + "nothing was taken."
        case .tenRaidsRepelled:
            return "Ten raids driven off. The colony is defending itself as a "
                + "matter of course."
        }
    }
}

/// A milestone and the day the colony reached it.
public struct MilestoneRecord: Codable, Equatable, Identifiable, Sendable {

    public let milestone: Milestone
    public let day: Int

    public init(milestone: Milestone, day: Int) {
        self.milestone = milestone
        self.day = day
    }

    public var id: Milestone { milestone }

    public var year: Int { day / Season.daysPerYear + 1 }
    public var season: Season { Season(day: day) }
}

/// What a colony has done, in the order it did it.
public struct Milestones: Codable, Equatable, Sendable {

    /// Oldest first. An array rather than a dictionary for the same reason
    /// `Almanac.tallies` is one: a `Dictionary` encodes in hash order, and a
    /// save file that differs between runs of the same simulation is a trap
    /// for anyone diffing two of them.
    public private(set) var achieved: [MilestoneRecord]

    public init(achieved: [MilestoneRecord] = []) {
        self.achieved = achieved
    }

    /// Decoded by hand so that a record this build no longer recognises is
    /// dropped rather than taking the whole save down with it.
    ///
    /// `Milestone` is a string-backed enum in a save file, which means a case
    /// renamed or retired in a later version is an unreadable colony —
    /// `GameStore.load` treats an unreadable save as no save, so that would
    /// silently delete somebody's bees. Losing one badge is the right price.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decodeIfPresent(
            [LenientRecord].self, forKey: .achieved
        ) ?? []
        achieved = stored.compactMap(\.record)
    }

    /// Decodes a record without insisting the milestone still exists.
    private struct LenientRecord: Decodable {
        let record: MilestoneRecord?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try container.decode(String.self, forKey: .milestone)
            let day = try container.decode(Int.self, forKey: .day)
            record = Milestone(rawValue: raw).map {
                MilestoneRecord(milestone: $0, day: day)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case milestone, day
        }
    }

    public func has(_ milestone: Milestone) -> Bool {
        achieved.contains { $0.milestone == milestone }
    }

    public var count: Int { achieved.count }

    public var isEmpty: Bool { achieved.isEmpty }

    /// The day a milestone was reached, or nil if it has not been.
    public func day(of milestone: Milestone) -> Int? {
        achieved.first { $0.milestone == milestone }?.day
    }

    /// The ones still to come, in declaration order, so the interface can show
    /// the player what is possible rather than only what is done.
    public var remaining: [Milestone] {
        Milestone.allCases.filter { !has($0) }
    }

    /// Records a milestone, ignoring one already held.
    ///
    /// - Returns: whether this was the first time. The system emits its event
    ///   on a true, which is what makes "awarded exactly once" a property of
    ///   this method rather than of every condition written above it.
    @discardableResult
    mutating func award(_ milestone: Milestone, onDay day: Int) -> Bool {
        guard !has(milestone) else { return false }
        achieved.append(MilestoneRecord(milestone: milestone, day: day))
        return true
    }
}
