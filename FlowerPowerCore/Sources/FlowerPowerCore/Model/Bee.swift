//
//  Bee.swift
//  FlowerPowerCore
//

import Foundation

public enum BeeKind: String, Codable, CaseIterable, Sendable {
    case queen
    case worker
    case drone

    public var displayName: String { rawValue.capitalized }

    /// Adult lifespan in days under normal conditions.
    public func baseAdultLifespanDays(physiology: WorkerPhysiology = .summer) -> Int {
        switch self {
        case .queen: return 730
        case .worker: return physiology.lifespanDays
        case .drone: return 55
        }
    }
}

/// Summer bees and winter bees are physiologically different animals.
///
/// A colony rears winter bees — "diutinus" bees — from late summer onward.
/// They carry heavy fat bodies, never work themselves out foraging, and live
/// six months instead of six weeks. They are the bees that carry the colony
/// through to spring, and rearing enough of them is the single most important
/// thing a colony does in autumn.
///
/// Modelling this matters: without it, autumn-reared bees died on a six-week
/// clock and every colony entered winter with a fraction of the cluster it
/// needed, then dwindled to nothing before the spring flow.
public enum WorkerPhysiology: String, Codable, CaseIterable, Sendable {
    case summer
    case winter

    public var lifespanDays: Int {
        switch self {
        case .summer: return 42
        // Diutinus bees live six to eight months. The upper end matters: the
        // dearth itself is six months, so a bee that lives exactly that long
        // dies the week before the first spring brood emerges.
        case .winter: return 220
        }
    }

    /// Winter bees are reared to survive rather than to work, and wear far
    /// more slowly on the few flights they do make.
    public var wearMultiplier: Double {
        switch self {
        case .summer: return 1.0
        case .winter: return 0.35
        }
    }

    /// Which kind of bee a colony is rearing on a given day. The switch happens
    /// in late summer, as day length shortens and brood rearing winds down.
    public init(rearedOn day: Int) {
        self = Season.isRearingWinterBees(on: day) ? .winter : .summer
    }

    public var displayName: String {
        switch self {
        case .summer: return "Summer Bee"
        case .winter: return "Winter Bee"
        }
    }
}

public enum DevelopmentStage: String, Codable, CaseIterable, Sendable {
    case egg
    case larva
    case pupa
    case adult

    public var displayName: String { rawValue.capitalized }

    public var next: DevelopmentStage? {
        switch self {
        case .egg: return .larva
        case .larva: return .pupa
        case .pupa: return .adult
        case .adult: return nil
        }
    }

    /// Sealed brood. Varroa can only reproduce inside capped cells, which is
    /// why mite population tracks brood rearing so closely.
    public var isCapped: Bool { self == .pupa }
}

/// Brood-development upgrades from the design doc, which shorten every
/// pre-adult stage.
public enum BroodUpgrade: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case first = 1
    case second = 2

    public var displayName: String {
        switch self {
        case .none: return "Natural"
        case .first: return "Accelerated"
        case .second: return "Rapid"
        }
    }
}

public enum BeeDevelopment {

    /// Days a bee of `kind` spends in `stage` at a given upgrade level.
    ///
    /// Features.md tabulates egg, larva and pupa as (3,2,1), (9,7,4) and
    /// queen (15,13,10) / worker (20,15,10) / drone (23,17,10). The third
    /// column is total days to emergence rather than pupa duration — it
    /// matches the real figures of 16, 21 and 24 days — so pupa duration is
    /// derived by subtracting the egg and larva stages.
    public static func days(
        for kind: BeeKind,
        stage: DevelopmentStage,
        upgrade: BroodUpgrade = .none
    ) -> Int {
        switch stage {
        case .egg:
            return [3, 2, 1][upgrade.rawValue]
        case .larva:
            return [9, 7, 4][upgrade.rawValue]
        case .pupa:
            let totalToEmergence: [Int]
            switch kind {
            case .queen: totalToEmergence = [15, 13, 10]
            case .worker: totalToEmergence = [20, 15, 10]
            case .drone: totalToEmergence = [23, 17, 10]
            }
            let elapsed = days(for: kind, stage: .egg, upgrade: upgrade)
                + days(for: kind, stage: .larva, upgrade: upgrade)
            return max(1, totalToEmergence[upgrade.rawValue] - elapsed)
        case .adult:
            return .max
        }
    }

    public static func totalDaysToEmergence(
        for kind: BeeKind,
        upgrade: BroodUpgrade = .none
    ) -> Int {
        days(for: kind, stage: .egg, upgrade: upgrade)
            + days(for: kind, stage: .larva, upgrade: upgrade)
            + days(for: kind, stage: .pupa, upgrade: upgrade)
    }
}

public enum WorkerJob: String, Codable, CaseIterable, Sendable {
    case cellCleaner
    case nurseBee
    case mortuary
    case droneFeeder
    case queenAttendant
    case nectarConcentrator
    case pollenPacker
    case honeycombBuilder
    case fanning
    case waterCarrier
    case guardBee
    case foragingBee

    public var displayName: String {
        switch self {
        case .cellCleaner: return "Cell Cleaner"
        case .nurseBee: return "Nurse"
        case .mortuary: return "Mortuary"
        case .droneFeeder: return "Drone Feeder"
        case .queenAttendant: return "Queen Attendant"
        case .nectarConcentrator: return "Nectar Concentrator"
        case .pollenPacker: return "Pollen Packer"
        case .honeycombBuilder: return "Comb Builder"
        case .fanning: return "Fanner"
        case .waterCarrier: return "Water Carrier"
        case .guardBee: return "Guard"
        case .foragingBee: return "Forager"
        }
    }

    /// Jobs performed outside the hive, which require the bee to be able to fly.
    public var requiresFlight: Bool {
        self == .foragingBee || self == .waterCarrier
    }

    /// Days of adult life during which a worker performs this job.
    ///
    /// These ranges deliberately overlap — a real worker holds several jobs at
    /// once. They must therefore be tested independently rather than in a
    /// `switch`, where first-match-wins would make the later ones unreachable.
    public var adultAgeRange: Range<Int> {
        switch self {
        case .cellCleaner: return 0..<2
        case .nurseBee: return 2..<11
        case .mortuary: return 3..<16
        case .droneFeeder: return 4..<13
        case .queenAttendant: return 7..<13
        case .nectarConcentrator: return 11..<20
        case .pollenPacker: return 12..<35
        case .honeycombBuilder: return 12..<35
        case .fanning: return 12..<35
        case .waterCarrier: return 0..<42     // all days
        case .guardBee: return 18..<21
        case .foragingBee: return 22..<42
        }
    }

    /// Oldest age the division-of-labour table describes. Beyond it a worker
    /// simply carries on doing the last job she had.
    public static let oldestWorkingAge = 41

    /// Every job an adult worker of this age is capable of.
    ///
    /// Ages past the end of the table clamp to it rather than falling off it.
    /// A bee older than the table is still a bee: real foragers work until they
    /// drop. Letting them age out left long-lived winter bees with no job at
    /// all, and a colony full of them simply stopped functioning.
    public static func jobs(forAdultAge age: Int) -> Set<WorkerJob> {
        let effectiveAge = min(max(0, age), oldestWorkingAge)
        return Set(allCases.filter { $0.adultAgeRange.contains(effectiveAge) })
    }
}

public struct Bee: Identifiable, Codable, Equatable, Sendable {

    public let id: EntityID
    public let kind: BeeKind
    public private(set) var stage: DevelopmentStage

    /// Days spent in the current stage. Once adult, this is the bee's adult age,
    /// which is what job eligibility keys off.
    public private(set) var daysInStage: Int

    /// Which of the queen's patrilines this bee descends from. Bees of the same
    /// patriline share a father and therefore share vulnerabilities.
    public let patriline: UInt8

    /// Condition at emergence and after, 0...1. Brood reared under mite
    /// pressure or on short rations emerges damaged and never recovers.
    public private(set) var vitality: Double

    /// Accumulated foraging effort. Real worker lifespan is governed less by
    /// calendar age than by how many kilometres she has flown, which is why
    /// winter bees live four times longer.
    public private(set) var wear: Double

    /// Job the player has pinned this bee to, overriding her age-appropriate
    /// work. Only jobs she is physically capable of will actually be performed.
    public var assignedJob: WorkerJob?

    /// Summer bee or winter bee. Fixed at emergence by the season she was
    /// reared in, and never changes afterwards.
    public private(set) var physiology: WorkerPhysiology

    /// Days of *working* life, which is what job eligibility keys off.
    ///
    /// Distinct from `daysInStage` because a winter bee's behavioural
    /// development is suspended in the cluster. She emerges in September, does
    /// essentially nothing for five months, and is still physiologically young
    /// in February — which is exactly why she is the bee that rears the first
    /// spring brood.
    ///
    /// Without this the two clocks were conflated, and every overwintered bee
    /// aged past the end of the job table. A colony would come through winter at
    /// full strength with no nurses, no foragers and no way to rebuild, then
    /// die in March. It looked like starvation; it was unemployment.
    public private(set) var behaviouralAge: Int

    public init(
        id: EntityID,
        kind: BeeKind,
        stage: DevelopmentStage = .egg,
        daysInStage: Int = 0,
        patriline: UInt8 = 0,
        vitality: Double = 1.0,
        wear: Double = 0,
        assignedJob: WorkerJob? = nil,
        physiology: WorkerPhysiology = .summer,
        behaviouralAge: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.stage = stage
        self.daysInStage = daysInStage
        self.patriline = patriline
        self.vitality = min(1, max(0, vitality))
        self.wear = wear
        self.assignedJob = assignedJob
        self.physiology = physiology
        self.behaviouralAge = behaviouralAge ?? daysInStage
    }

    // MARK: - Condition

    public var isAdult: Bool { stage == .adult }
    public var isBrood: Bool { stage != .adult }

    /// Deformed wing virus leaves bees that physically cannot fly. They survive
    /// inside the hive but can never forage, so a heavily infested colony
    /// starves surrounded by nurses.
    public var canFly: Bool { vitality >= 0.35 }

    /// Work output multiplier. A damaged bee still contributes, just less.
    public var effectiveness: Double { 0.35 + 0.65 * vitality }

    /// Jobs this bee can currently perform, accounting for her assignment, her
    /// age, and whether she is physically able.
    public var jobs: Set<WorkerJob> {
        guard kind == .worker, stage == .adult else { return [] }

        // A pinned job the bee can actually do wins. One she cannot — because
        // she is too young, or too damaged to fly — is quietly ignored rather
        // than leaving her idle: the player asked for something impossible, and
        // a bee standing about doing nothing is a worse answer than a bee
        // getting on with her own work.
        if let assigned = assignedJob, isCapable(of: assigned) {
            return [assigned]
        }

        return Set(WorkerJob.allCases.filter(isCapable(of:)))
    }

    /// Whether this bee is doing `job` right now.
    ///
    /// Deliberately allocation-free. The obvious implementation is
    /// `jobs.contains(job)`, but `jobs` builds a `Set`, and the systems ask this
    /// question for every bee, for roughly ten jobs, every tick. On a colony of
    /// several hundred that is tens of thousands of `Set` allocations per
    /// simulated hour — enough to make a week's offline catch-up visibly slow on
    /// a phone, and enough to make the balance tooling unusable.
    public func performs(_ job: WorkerJob) -> Bool {
        guard kind == .worker, stage == .adult else { return false }

        // Mirrors `jobs`: an impossible assignment falls back to natural work.
        if let assigned = assignedJob, isCapable(of: assigned) {
            return assigned == job
        }

        return isCapable(of: job)
    }

    /// Whether her age, physiology and condition allow this work at all.
    public func isCapable(of job: WorkerJob) -> Bool {
        guard kind == .worker, stage == .adult else { return false }
        if job.requiresFlight, !canFly { return false }

        // A winter bee is a generalist, and that is the whole point of her.
        //
        // She has never fed brood, so her glands are intact and she can nurse;
        // she is months old, so she can fly and forage the first warm day. A
        // wintered colony has nothing else to work with, and every job it needs
        // in February and March falls to these bees.
        //
        // Restricting them to their behavioural age broke spring twice over:
        // frozen at age zero they were cell cleaners and the colony had no
        // nurses, and once they began ageing they were nurses and the colony had
        // no foragers for three weeks — long enough to burn through the winter
        // stores and starve in April with the flow just starting.
        if physiology == .winter { return true }

        let effectiveAge = min(max(0, behaviouralAge), WorkerJob.oldestWorkingAge)
        return job.adultAgeRange.contains(effectiveAge)
    }

    // MARK: - Mutation

    public mutating func damage(_ amount: Double) {
        vitality = min(1, max(0, vitality - amount))
    }

    public mutating func recover(_ amount: Double) {
        vitality = min(1, max(0, vitality + amount))
    }

    /// Records the cost of a day's work. Foraging is by far the most punishing,
    /// and winter bees are built to shrug it off.
    public mutating func accumulateWear(_ amount: Double) {
        wear += max(0, amount) * physiology.wearMultiplier
    }

    /// Total lifespan in days, after condition. Wear counts against it, so a
    /// hard-foraging bee reaches the end sooner than the calendar suggests.
    ///
    /// The queen's life is far less sensitive to condition than a worker's, and
    /// deliberately so. Her condition swings with the royal jelly supply, which
    /// is inherently bursty — and when lifespan tracked that swing closely she
    /// dropped dead in her first autumn on a single lean week, at a moment the
    /// colony was broodless and could not raise a successor. Queens should fail
    /// gradually and be *superseded*, which is the mechanism the colony
    /// actually has for replacing them; they should not die of a bad fortnight.
    public var effectiveLifespanDays: Double {
        let base = Double(kind.baseAdultLifespanDays(physiology: physiology))
        let conditionFactor = kind == .queen
            ? 0.85 + 0.15 * vitality
            : 0.55 + 0.45 * vitality
        return base * conditionFactor
    }

    /// Advances one day. Returns the outcome so the simulation can emit events
    /// rather than silently mutating state.
    ///
    /// - Parameter day: the day she is emerging on, which fixes whether she
    ///   becomes a six-week summer bee or a six-month winter bee.
    public mutating func advanceOneDay(
        upgrade: BroodUpgrade,
        day: Int
    ) -> DayOutcome {
        daysInStage += 1

        if stage == .adult {
            // A clustered winter bee is not working, so she is not ageing
            // behaviourally either. Her calendar age still runs.
            if !isBehaviourallyDormant(on: day) {
                behaviouralAge += 1
            }

            let consumed = Double(daysInStage) + wear
            return consumed >= effectiveLifespanDays ? .diedOfOldAge : .aged
        }

        let required = BeeDevelopment.days(for: kind, stage: stage, upgrade: upgrade)
        guard daysInStage >= required, let next = stage.next else { return .aged }

        stage = next
        daysInStage = 0

        if next == .adult {
            physiology = WorkerPhysiology(rearedOn: day)
            behaviouralAge = 0
        }

        return .advancedTo(next)
    }

    /// Whether this bee is sitting out the dearth rather than working.
    ///
    /// Dormancy has to *end* before the spring build-up, not at the equinox.
    /// Freezing winter bees at behavioural age zero right through winter left
    /// them permanently cell cleaners: the colony had no nurses at the exact
    /// moment it needed to rear its first brood of the year, so it could not
    /// restart and died in March with full stores.
    private func isBehaviourallyDormant(on day: Int) -> Bool {
        guard kind == .worker, physiology == .winter else { return false }
        return Season.isClusterDormant(on: day)
    }

    public enum DayOutcome: Equatable, Sendable {
        case aged
        case advancedTo(DevelopmentStage)
        case diedOfOldAge
    }
}
