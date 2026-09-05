//
//  Hive.swift
//  FlowerPowerCore
//

import Foundation

// MARK: - Site

public enum HiveLocationType: String, Codable, CaseIterable, Sendable {
    case livingTreeCavity
    case fallenTree
    case underTreeBranch
    case cliff
    case cave
    case insideWalls
    case humanStructure
    case termiteMound
    case animalBurrow
    case nestbox

    public var displayName: String {
        switch self {
        case .livingTreeCavity: return "Living Tree Cavity"
        case .fallenTree: return "Fallen Tree"
        case .underTreeBranch: return "Under a Branch"
        case .cliff: return "Cliff Face"
        case .cave: return "Cave"
        case .insideWalls: return "Inside a Wall"
        case .humanStructure: return "Human Structure"
        case .termiteMound: return "Termite Mound"
        case .animalBurrow: return "Animal Burrow"
        case .nestbox: return "Nest Box"
        }
    }

    /// How well the cavity holds temperature. Exposed sites cost far more honey
    /// to keep warm through winter.
    public var insulation: Double {
        switch self {
        case .livingTreeCavity: return 0.85
        case .fallenTree: return 0.70
        case .underTreeBranch: return 0.25
        case .cliff: return 0.50
        case .cave: return 0.90
        case .insideWalls: return 0.90
        case .humanStructure: return 0.80
        case .termiteMound: return 0.75
        case .animalBurrow: return 0.80
        case .nestbox: return 0.70
        }
    }

    /// Comb cells the site can eventually hold.
    public var maximumCells: Int {
        switch self {
        case .cave, .insideWalls: return 900
        case .livingTreeCavity, .humanStructure, .animalBurrow: return 700
        case .fallenTree, .termiteMound, .nestbox: return 500
        case .cliff: return 350
        case .underTreeBranch: return 200
        }
    }

    /// How easily a raider gets in. An open branch nest is indefensible; a
    /// cavity with a small entrance can be held by a handful of guards.
    public var defensibility: Double {
        switch self {
        case .livingTreeCavity: return 0.85
        case .insideWalls: return 0.90
        case .cave: return 0.60
        case .humanStructure: return 0.75
        case .animalBurrow: return 0.55
        case .termiteMound: return 0.80
        case .fallenTree: return 0.50
        case .nestbox: return 0.65
        case .cliff: return 0.55
        case .underTreeBranch: return 0.15
        }
    }

    /// Ground-level sites attract mammals; exposed sites attract birds.
    public var groundPredatorExposure: Double {
        switch self {
        case .animalBurrow, .fallenTree, .termiteMound: return 1.0
        case .nestbox, .humanStructure, .insideWalls: return 0.6
        case .cave: return 0.7
        case .livingTreeCavity: return 0.35
        case .cliff, .underTreeBranch: return 0.2
        }
    }
}

public struct HiveLocation: Codable, Equatable, Sendable {

    public var coordinate: GeoPoint?
    public var type: HiveLocationType

    public init(coordinate: GeoPoint? = nil, type: HiveLocationType) {
        self.coordinate = coordinate
        self.type = type
    }
}

// MARK: - Pheromones

/// Chemical signalling. Bees have no central authority — every colony-level
/// decision emerges from these gradients, so modelling them explicitly is what
/// lets swarming, supersedure and foraging drive emerge rather than be scripted.
public struct Pheromones: Codable, Equatable, Sendable {

    /// Queen mandibular pheromone, 0...1. Signals "the queen is here and well".
    /// It suppresses queen rearing and worker ovary development. It is
    /// distributed by contact, so it thins out as the colony grows — which is
    /// precisely why big colonies swarm.
    public var queenMandibular: Double

    /// Open brood signal, 0...1. Stimulates foraging and pollen collection.
    public var brood: Double

    /// Alarm pheromone, 0...1. Spikes during an attack and recruits defenders.
    public var alarm: Double

    /// Nasonov, the orientation signal used to gather a swarm and mark the
    /// hive entrance.
    public var nasonov: Double

    public init(
        queenMandibular: Double = 1.0,
        brood: Double = 0,
        alarm: Double = 0,
        nasonov: Double = 0
    ) {
        self.queenMandibular = queenMandibular
        self.brood = brood
        self.alarm = alarm
        self.nasonov = nasonov
    }

    /// Below this, workers start building queen cells.
    public static let queenRearingThreshold: Double = 0.45

    /// Below this, workers begin laying unfertilised eggs — the terminal state
    /// of a queenless colony.
    public static let layingWorkerThreshold: Double = 0.12
}

// MARK: - Hive

public struct Hive: Codable, Equatable, Sendable {

    public var location: HiveLocation
    public var bees: [Bee]
    public var resources: ResourcePool
    public var comb: Comb

    /// Brood-nest temperature in Celsius. Healthy brood needs 34-35C.
    public var temperatureCelsius: Double
    /// Nest humidity, 0...1. Bees hold it near 0.6; too dry kills brood, too
    /// damp breeds chalkbrood.
    public var humidity: Double

    public var pathogens: PathogenLoad
    public var pheromones: Pheromones
    public var genetics: QueenGenetics
    public var broodUpgrade: BroodUpgrade

    /// Days since the colony last had a laying queen. Past about three weeks a
    /// queenless colony can no longer rear one, because there is no young brood
    /// left to rear her from.
    public var daysQueenless: Int

    /// Set once workers begin laying. Terminal — such a colony produces only
    /// drones and dwindles.
    public var hasLayingWorkers: Bool

    /// A newly emerged queen is a virgin and lays nothing until she has flown
    /// to a drone congregation area and mated. That flight is the single most
    /// dangerous moment in a colony's life: bad weather or a hungry bird during
    /// the mating window ends the whole lineage.
    public var queenIsMated: Bool

    /// Propolis sealing, 0...1. Reduces draughts and suppresses pathogens.
    public var propolisEnvelope: Double

    public init(
        location: HiveLocation,
        bees: [Bee] = [],
        resources: ResourcePool = ResourcePool(),
        comb: Comb? = nil,
        temperatureCelsius: Double = 35,
        humidity: Double = 0.6,
        pathogens: PathogenLoad = PathogenLoad(),
        pheromones: Pheromones = Pheromones(),
        genetics: QueenGenetics = .standard,
        broodUpgrade: BroodUpgrade = .none,
        daysQueenless: Int = 0,
        hasLayingWorkers: Bool = false,
        queenIsMated: Bool = true,
        propolisEnvelope: Double = 0
    ) {
        self.location = location
        self.bees = bees
        self.resources = resources
        self.comb = comb ?? Comb(capacity: location.type.maximumCells)
        self.temperatureCelsius = temperatureCelsius
        self.humidity = humidity
        self.pathogens = pathogens
        self.pheromones = pheromones
        self.genetics = genetics
        self.broodUpgrade = broodUpgrade
        self.daysQueenless = daysQueenless
        self.hasLayingWorkers = hasLayingWorkers
        self.queenIsMated = queenIsMated
        self.propolisEnvelope = propolisEnvelope
    }

    /// Workers in the founding swarm.
    ///
    /// Features.md specifies a queen, two drones and three workers. Three
    /// workers is not a colony — one forager cannot gather enough to feed even
    /// a single frame of brood, so a literal reading collapses inside six
    /// weeks every single time. It was tried; it died on day 38.
    ///
    /// The composition is kept and the workforce scaled to a small cast swarm,
    /// which is what actually arrives at an empty cavity looking for a home.
    public static let foundingWorkerCount = 24

    /// The founding colony: a queen, two drones, and a swarm of workers spread
    /// across every age, arriving with honey in their crops.
    public static func newColony(
        at location: HiveLocation,
        ids: inout IDGenerator,
        genetics: QueenGenetics = .standard,
        workerCount: Int = foundingWorkerCount
    ) -> Hive {
        var bees: [Bee] = [
            Bee(id: ids.next(), kind: .queen, stage: .adult, daysInStage: 10)
        ]

        for _ in 0..<2 {
            bees.append(Bee(id: ids.next(), kind: .drone, stage: .adult, daysInStage: 12))
        }

        // Ages are spread across the whole working life so the colony starts
        // with foragers gathering, house bees ripening and building, and nurses
        // ready for the queen's first brood. A cohort of same-age bees would
        // all age out of foraging on the same day and strand the colony.
        for index in 0..<max(1, workerCount) {
            let age = 2 + (index * 38) / max(1, workerCount)
            bees.append(Bee(
                id: ids.next(),
                kind: .worker,
                stage: .adult,
                daysInStage: age,
                patriline: UInt8(index % max(1, genetics.patrilines))
            ))
        }

        return Hive(
            location: location,
            bees: bees,
            // A swarm carries several days of food in the bees themselves.
            resources: ResourcePool([.honey: 60, .pollen: 20, .wax: 10]),
            comb: Comb(workerCells: 60, droneCells: 6, capacity: location.type.maximumCells),
            genetics: genetics
        )
    }

    // MARK: - Population

    public var queen: Bee? {
        bees.first { $0.kind == .queen && $0.stage == .adult }
    }

    public var isQueenright: Bool { queen != nil }

    /// A queen who is present, mated, and therefore actually laying.
    public var hasLayingQueen: Bool { isQueenright && queenIsMated }

    /// A virgin queen who still has to make her mating flight.
    public var hasVirginQueen: Bool { isQueenright && !queenIsMated }

    /// A colony with no queen and no young brood cannot recover on its own.
    public var canStillRearAQueen: Bool {
        bees.contains { $0.kind == .worker && ($0.stage == .egg || $0.stage == .larva) }
    }

    public func count(kind: BeeKind, stage: DevelopmentStage) -> Int {
        bees.filter { $0.kind == kind && $0.stage == stage }.count
    }

    public func count(kind: BeeKind) -> Int {
        bees.filter { $0.kind == kind }.count
    }

    /// Adult workers currently able to perform `job`.
    public func workers(performing job: WorkerJob) -> [Bee] {
        bees.filter { $0.performs(job) }
    }

    public func count(performing job: WorkerJob) -> Int {
        bees.filter { $0.performs(job) }.count
    }

    /// Effective workforce for a job, weighted by each bee's condition. A
    /// hundred virus-damaged bees do not do the work of a hundred healthy ones.
    public func workforce(for job: WorkerJob) -> Double {
        bees.reduce(0) { $0 + ($1.performs(job) ? $1.effectiveness : 0) }
    }

    public var broodCount: Int { bees.filter { $0.isBrood }.count }
    public var cappedBroodCount: Int { bees.filter { $0.stage == .pupa }.count }
    public var openBroodCount: Int {
        bees.filter { $0.stage == .egg || $0.stage == .larva }.count
    }
    public var adultCount: Int { bees.filter { $0.isAdult }.count }

    /// Whether the colony is finished — not dying, finished.
    ///
    /// Two ways to be over, and both are terminal in the strict sense that no
    /// action by the player and no luck in the simulation can reverse them.
    ///
    /// 1. No adults left. Sealed brood in an empty nest is not a colony that
    ///    might recover: there is nobody to feed it, nobody to hold it at 35
    ///    degrees, and nobody to uncap it.
    /// 2. Queenless with no way to make a queen. Emergency queens are grafted
    ///    from worker eggs and young larvae; with none of those, no queen
    ///    cells under way, and no queen laying, the colony cannot produce
    ///    another worker. From there the population can only fall.
    ///
    /// The second is what catches the common endings — a failed mating flight,
    /// laying workers — which otherwise leave the player watching a colony of
    /// drones dwindle for weeks with nothing to do and nothing to read but
    /// "Critical".
    ///
    /// A colony that is merely in serious trouble is `critical`, and the
    /// interface should push the player to act, because those can be saved.
    /// Collapse is the state with nothing left to decide.
    public var isCollapsed: Bool {
        if adultCount == 0 { return true }
        return !canRearWorkers && !couldStillGetAQueen
    }

    /// Whether any worker will ever be born here again.
    ///
    /// Needs a queen who is present, mated, and mated *properly*. A drone
    /// layer — a queen who ran out of sperm, or never got enough on her
    /// mating flight — is a queen in every visible sense and lays every day,
    /// but every egg is a drone.
    public var canRearWorkers: Bool {
        isQueenright && queenIsMated && genetics.isProperlyMated
    }

    /// Whether a queen who could rear workers might still turn up.
    ///
    /// Three routes, and a colony only needs one: worker eggs or young larvae
    /// it can graft an emergency queen from, a queen cell already under way,
    /// or a virgin queen who has not yet had her mating flight. A virgin
    /// counts — she may well fail, and often does, but it has not happened
    /// yet and the colony is not finished until it has.
    public var couldStillGetAQueen: Bool {
        canStillRearAQueen
            || comb.hasQueenCells
            || (isQueenright && !queenIsMated)
    }
    public var adultWorkerCount: Int {
        bees.filter { $0.kind == .worker && $0.isAdult }.count
    }
    public var population: Int { bees.count }

    /// Mean condition of the adult workforce, 0...1.
    public var averageVitality: Double {
        let adults = bees.filter(\.isAdult)
        guard !adults.isEmpty else { return 0 }
        return adults.reduce(0) { $0 + $1.vitality } / Double(adults.count)
    }

    // MARK: - Comb and stores

    public var cellsOccupiedByBrood: Int { broodCount }
    public var cellsOccupiedByStores: Int { resources.cellsOccupied }

    public var freeCells: Int {
        max(0, comb.builtCells - cellsOccupiedByBrood - cellsOccupiedByStores)
    }

    /// Cells available for the queen to lay in, which excludes drone comb when
    /// laying worker brood.
    public func layingSpace(for kind: BeeKind) -> Int {
        let typed = kind == .drone ? comb[.drone] : comb[.worker]
        let share = comb.builtCells > 0 ? Double(typed) / Double(comb.builtCells) : 0
        return Int(Double(freeCells) * share)
    }

    public var maximumCells: Int { comb.capacity }
    public var canBuildMoreCells: Bool { comb.canExpand }

    /// How full the drawn comb is, 0...1. This is what tells the colony to
    /// build more.
    public var combOccupancy: Double {
        guard comb.builtCells > 0 else { return 1 }
        let used = Double(cellsOccupiedByBrood + cellsOccupiedByStores)
        return min(1, used / Double(comb.builtCells))
    }

    /// How much of the cavity the colony has actually drawn out, 0...1.
    public var cavityFilled: Double {
        guard comb.capacity > 0 else { return 1 }
        return min(1, Double(comb.builtCells) / Double(comb.capacity))
    }

    /// Pressure toward swarming, 0...1.
    ///
    /// Distinct from `combOccupancy`: a colony with full comb but plenty of
    /// cavity left draws more comb rather than dividing. But it is a matter of
    /// degree, not a hard gate — colonies routinely swarm from hives with empty
    /// frames still in them, because what they are really responding to is
    /// crowding in the brood nest.
    ///
    /// The earlier version multiplied by a flat 0.6 whenever any expansion room
    /// remained, which capped this below the swarm threshold and made swarming
    /// literally unreachable. Thirty test colonies produced zero swarms.
    public var swarmPressure: Double {
        combOccupancy * (0.75 + 0.25 * cavityFilled)
    }

    /// Honey a wintering bee eats over the whole dearth — autumn through to the
    /// first spring forage — between its own metabolism and its share of
    /// keeping the cluster warm.
    public static let winterHoneyPerBee: Double = 2.8

    /// Honey the colony needs banked to survive the coming winter.
    ///
    /// Scales with the cluster that will actually have to be fed. A fixed
    /// figure looks reasonable until a colony triples in size: it then provisions
    /// for a hive a quarter its own strength, sails into November looking
    /// magnificent, and starves. That failure took survival from 70% to 3%.
    public var winterStoresRequired: Double {
        // A colony still shrinking toward its winter cluster should provision
        // for the cluster, not for its summer peak — but never for less than a
        // viable minimum.
        let cluster = max(60.0, Double(adultCount))

        let insulationPenalty = 1.0 + (1.0 - location.type.insulation)
        let thrift = 1.0 - 0.25 * genetics.thriftiness

        return cluster * Self.winterHoneyPerBee * insulationPenalty * thrift
    }

    public var isWinterReady: Bool {
        resources.edibleEnergy >= winterStoresRequired
    }
}
