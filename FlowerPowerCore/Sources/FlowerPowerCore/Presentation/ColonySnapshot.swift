//
//  ColonySnapshot.swift
//  FlowerPowerCore
//
//  A read-only, self-describing view of the colony for the interface to render.
//
//  The UI never reaches into `Hive` or `World`. It asks for a snapshot and
//  displays what it finds. That keeps SwiftUI out of the simulation's business,
//  lets the watch and the phone share one vocabulary, and means the engine can
//  be restructured without touching a single view.
//

import Foundation

// MARK: - Status

public enum ColonyStatus: Int, Codable, Comparable, Sendable, CaseIterable {
    /// The colony is dead. Not dying — dead, with nothing left that can rear a
    /// queen or hold a cluster.
    ///
    /// This is deliberately distinct from `critical`. A critical colony is one
    /// the player might still save, and every interface affordance should push
    /// them to try. A collapsed one cannot be saved, and showing it as
    /// "Critical" for ever was the game's worst dead end: the numbers simply
    /// stopped moving and nothing said why or what to do.
    ///
    /// Raw value -1 rather than renumbering the others, so saves written before
    /// this case existed still decode.
    case collapsed = -1
    case critical = 0
    case struggling
    case steady
    case thriving

    public static func < (lhs: ColonyStatus, rhs: ColonyStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .collapsed: return "Collapsed"
        case .critical: return "Critical"
        case .struggling: return "Struggling"
        case .steady: return "Steady"
        case .thriving: return "Thriving"
        }
    }

    /// Whether there is still a colony to play. Everything the player can do
    /// is gated on this.
    public var isAlive: Bool { self != .collapsed }

    /// SF Symbol name, so both apps show the same icon for the same state.
    public var symbolName: String {
        switch self {
        case .collapsed: return "xmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        case .struggling: return "exclamationmark.circle"
        case .steady: return "equal.circle"
        case .thriving: return "arrow.up.circle.fill"
        }
    }
}

// MARK: - Alerts

public struct ColonyAlert: Identifiable, Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case queenless
        case queenFailing
        case layingWorkers
        case starving
        case winterStoresLow
        case disease
        case underAttack
        case tooCold
        case tooHot
        case noForage
        case crowded
        case swarmPreparing
        case foragersIdle
    }

    public var id: String { kind.rawValue }

    public let kind: Kind
    public let severity: SimEvent.Severity
    public let title: String
    public let detail: String
    /// What the player can actually do about it, if anything.
    public let suggestion: String?

    public init(
        kind: Kind,
        severity: SimEvent.Severity,
        title: String,
        detail: String,
        suggestion: String? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
    }
}

// MARK: - Sections

public struct PopulationSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let adults: Int
    public let brood: Int
    public let workers: Int
    public let drones: Int
    public let eggs: Int
    public let larvae: Int
    public let pupae: Int
    public let winterBees: Int
    /// Effective workforce per job, so the interface can draw the job breakdown
    /// the design doc's HiveHealthView calls for.
    public let jobs: [WorkerJob: Int]
    public let averageVitality: Double
}

public struct StoresSummary: Codable, Equatable, Sendable {
    public let resources: [ResourceKind: Double]
    public let edibleEnergy: Double
    public let winterRequirement: Double
    /// 0...1, clamped. The single number that decides whether the colony sees
    /// spring, and the one the watch complication shows in autumn.
    public let winterReadiness: Double
    public let isWinterReady: Bool
}

public struct NestSummary: Codable, Equatable, Sendable {
    public let siteType: HiveLocationType
    /// Where the hive stands, when the player has placed it. The map needs this
    /// to centre itself and to draw the foraging range.
    public let coordinate: GeoPoint?
    public let builtCells: Int
    public let capacity: Int
    public let freeCells: Int
    public let combOccupancy: Double
    public let temperatureCelsius: Double
    public let humidity: Double
    public let propolisEnvelope: Double
    public let queenCells: [QueenCell.Purpose]
}

public struct HealthSummary: Codable, Equatable, Sendable {
    public let infections: [Pathogen: Double]
    public let dominantInfection: Pathogen?
    public let totalPressure: Double
    public let recentAttacks: [Predator]
}

public struct QueenSummary: Codable, Equatable, Sendable {

    public enum State: String, Codable, Sendable {
        case laying
        case virgin
        case droneLayer
        case absent
        case layingWorkers

        public var displayName: String {
            switch self {
            case .laying: return "Laying"
            case .virgin: return "Virgin"
            case .droneLayer: return "Drone Layer"
            case .absent: return "No Queen"
            case .layingWorkers: return "Laying Workers"
            }
        }
    }

    public let state: State
    public let ageDays: Int
    public let vitality: Double
    public let patrilines: Int
    public let geneticDiversity: Double
    public let hygienicBehaviour: Double
    public let daysQueenless: Int
    public let queenPheromone: Double
}

public struct PatchSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: EntityID
    public let photoLocalIdentifier: String
    public let speciesName: String
    public let isIdentified: Bool
    public let rarity: FlowerRarity
    public let coordinate: GeoPoint?
    public let distanceMetres: Double
    /// Whether the bees can work it *right now*: in season, still there, and
    /// not stripped. This is the flag the garden and the map colour by.
    public let isInBloom: Bool
    public let isWithinRange: Bool
    /// 0...1 of its standing capacity.
    public let remainingFraction: Double
    public let foragersWorkingIt: Int
    public let discoveredAt: Date

    /// How much of the stand is left, from 1 down to 0, as the photograph ages
    /// out. Shown so the player can see a patch going before it is gone, and
    /// knows to photograph a replacement.
    public let vigour: Double

    /// Past its best but not yet gone. The cue to go out again.
    public var isFading: Bool { vigour < 0.999 && vigour > 0 }

    /// The stand is no longer there.
    public var hasFaded: Bool { vigour <= 0 }
}

// MARK: - Snapshot

public struct ColonySnapshot: Codable, Equatable, Sendable {

    public let day: Int
    public let season: Season
    public let hourOfDay: Int
    public let weather: Weather

    public let status: ColonyStatus
    public let headline: String

    public let population: PopulationSummary
    public let stores: StoresSummary
    public let nest: NestSummary
    public let health: HealthSummary
    public let queen: QueenSummary
    public let patches: [PatchSummary]
    public let alerts: [ColonyAlert]

    /// Whether the bees are out working right now — the thing a player glancing
    /// at the app most wants to know.
    public let isForaging: Bool
    public let dailyNectarIntake: Double
}

// MARK: - Building

extension Simulation {

    /// Renders the current state for display.
    public func snapshot() -> ColonySnapshot {
        let hive = world.hive
        let season = self.season

        return ColonySnapshot(
            day: clock.day,
            season: season,
            hourOfDay: clock.hourOfDay,
            weather: world.weather,
            status: colonyStatus(),
            headline: headline(),
            population: populationSummary(),
            stores: storesSummary(),
            nest: nestSummary(),
            health: healthSummary(),
            queen: queenSummary(),
            patches: patchSummaries(),
            alerts: alerts(),
            isForaging: clock.isDaylight
                && world.weather.isFlyingWeather
                && hive.count(performing: .foragingBee) > 0,
            dailyNectarIntake: world.recentNectarIntake.last ?? world.todayNectarIntake
        )
    }

    // MARK: Sections

    private func populationSummary() -> PopulationSummary {
        let hive = world.hive

        var jobs: [WorkerJob: Int] = [:]
        for job in WorkerJob.allCases {
            let count = hive.count(performing: job)
            if count > 0 { jobs[job] = count }
        }

        return PopulationSummary(
            total: hive.population,
            adults: hive.adultCount,
            brood: hive.broodCount,
            workers: hive.count(kind: .worker),
            drones: hive.count(kind: .drone),
            eggs: hive.bees.filter { $0.stage == .egg }.count,
            larvae: hive.bees.filter { $0.stage == .larva }.count,
            pupae: hive.bees.filter { $0.stage == .pupa }.count,
            winterBees: hive.bees.filter { $0.isAdult && $0.physiology == .winter }.count,
            jobs: jobs,
            averageVitality: hive.averageVitality
        )
    }

    private func storesSummary() -> StoresSummary {
        let hive = world.hive
        let requirement = hive.winterStoresRequired

        return StoresSummary(
            resources: hive.resources.stored,
            edibleEnergy: hive.resources.edibleEnergy,
            winterRequirement: requirement,
            winterReadiness: requirement > 0
                ? min(1, hive.resources.edibleEnergy / requirement)
                : 1,
            isWinterReady: hive.isWinterReady
        )
    }

    private func nestSummary() -> NestSummary {
        let hive = world.hive
        return NestSummary(
            siteType: hive.location.type,
            coordinate: hive.location.coordinate,
            builtCells: hive.comb.builtCells,
            capacity: hive.comb.capacity,
            freeCells: hive.freeCells,
            combOccupancy: hive.combOccupancy,
            temperatureCelsius: hive.temperatureCelsius,
            humidity: hive.humidity,
            propolisEnvelope: hive.propolisEnvelope,
            queenCells: hive.comb.queenCells.map(\.purpose)
        )
    }

    private func healthSummary() -> HealthSummary {
        let hive = world.hive
        return HealthSummary(
            infections: hive.pathogens.active,
            dominantInfection: hive.pathogens.dominant?.pathogen,
            totalPressure: hive.pathogens.totalPressure,
            recentAttacks: world.attackHistory
                .filter { clock.day - $0.day <= 14 }
                .map(\.predator)
        )
    }

    private func queenSummary() -> QueenSummary {
        let hive = world.hive

        let state: QueenSummary.State
        if hive.hasLayingWorkers {
            state = .layingWorkers
        } else if !hive.isQueenright {
            state = .absent
        } else if !hive.queenIsMated {
            state = .virgin
        } else if !hive.genetics.isProperlyMated {
            state = .droneLayer
        } else {
            state = .laying
        }

        return QueenSummary(
            state: state,
            ageDays: hive.queen?.daysInStage ?? 0,
            vitality: hive.queen?.vitality ?? 0,
            patrilines: hive.genetics.patrilines,
            geneticDiversity: hive.genetics.geneticDiversity,
            hygienicBehaviour: hive.genetics.hygienicBehaviour,
            daysQueenless: hive.daysQueenless,
            queenPheromone: hive.pheromones.queenMandibular
        )
    }

    private func patchSummaries() -> [PatchSummary] {
        let season = self.season
        let day = clock.day
        let config = self.config

        return world.patches.map { patch in
            let capacity = patch.nectarCapacity + patch.pollenCapacity
            let remaining = patch.remainingNectar + patch.remainingPollen
            let vigour = patch.vigour(onDay: day, config: config)

            return PatchSummary(
                id: patch.id,
                photoLocalIdentifier: patch.photoLocalIdentifier,
                speciesName: patch.resolvedSpecies.commonName,
                isIdentified: patch.isIdentified,
                rarity: patch.resolvedSpecies.rarity,
                coordinate: patch.coordinate,
                distanceMetres: patch.distanceMetres,
                isInBloom: patch.isInBloom(during: season) && vigour > 0,
                isWithinRange: patch.isWithinRange,
                remainingFraction: capacity > 0 ? remaining / capacity : 0,
                foragersWorkingIt: patch.recruitedForagers,
                discoveredAt: patch.discoveredAt,
                vigour: vigour
            )
        }
        // Best forage first: that is the order a player wants to scan.
        .sorted { lhs, rhs in
            if lhs.isInBloom != rhs.isInBloom { return lhs.isInBloom }
            return lhs.remainingFraction > rhs.remainingFraction
        }
    }

    // MARK: Judgement

    private func colonyStatus() -> ColonyStatus {
        let hive = world.hive

        if hive.isCollapsed { return .collapsed }

        if hive.hasLayingWorkers { return .critical }
        if !hive.isQueenright && !hive.canStillRearAQueen && !hive.comb.hasQueenCells {
            return .critical
        }
        if hive.adultWorkerCount < config.minimumViablePopulation { return .critical }
        if hive.resources.edibleEnergy < config.layingEnergyThreshold { return .critical }

        if !hive.isQueenright { return .struggling }
        if hive.pathogens.totalPressure > 0.5 { return .struggling }
        if hive.averageVitality < 0.6 { return .struggling }
        if season == .autumn && !hive.isWinterReady { return .struggling }

        if hive.broodCount > 0, hive.isWinterReady || season != .autumn,
           hive.averageVitality > 0.85 {
            return .thriving
        }

        return .steady
    }

    /// One sentence describing what the colony is doing. Written for a glance,
    /// which on the watch may be all the player ever reads.
    private func headline() -> String {
        let hive = world.hive

        if hive.isCollapsed { return "The colony is gone." }
        if hive.hasLayingWorkers { return "Laying workers — the colony is failing." }
        if !hive.isQueenright {
            return hive.comb.hasQueenCells
                ? "Queenless, raising a new queen."
                : "Queenless, with no replacement under way."
        }
        if !hive.queenIsMated { return "A virgin queen is waiting to fly." }
        if !hive.genetics.isProperlyMated { return "The queen is laying only drones." }

        if !world.weather.isFlyingWeather {
            return "Grounded by the weather — no foraging today."
        }
        if season == .winter { return "Clustered for winter." }
        if world.patches.isEmpty { return "No flowers found yet. Photograph some." }

        let bloomingPatches = world.patches.filter {
            $0.isInBloom(during: season)
                && !$0.isDepleted
                && !$0.hasFaded(onDay: clock.day, config: config)
        }
        if bloomingPatches.isEmpty {
            // Distinguish "wrong time of year" from "your flowers are gone",
            // because only one of them is something the player can fix today.
            let anyStanding = world.patches.contains {
                !$0.hasFaded(onDay: clock.day, config: config)
            }
            return anyStanding
                ? "Nothing in bloom nearby."
                : "The flowers you found have gone over. Photograph more."
        }

        if world.isInFlow { return "The nectar is flowing." }
        if world.isInDearth { return "A dearth — little is coming in." }
        if hive.comb.queenCells.contains(where: { $0.purpose == .swarm }) {
            return "Preparing to swarm."
        }

        return "Foraging steadily."
    }

    private func alerts() -> [ColonyAlert] {
        let hive = world.hive
        var alerts: [ColonyAlert] = []

        if hive.hasLayingWorkers {
            alerts.append(ColonyAlert(
                kind: .layingWorkers,
                severity: .critical,
                title: "Laying Workers",
                detail: "Workers have begun laying unfertilised eggs. The colony can only produce drones now.",
                suggestion: "This colony cannot recover on its own."
            ))
        } else if !hive.isQueenright {
            alerts.append(ColonyAlert(
                kind: .queenless,
                severity: .critical,
                title: "No Queen",
                detail: hive.comb.hasQueenCells
                    ? "Queenless for \(hive.daysQueenless) days, with \(hive.comb.queenCells.count) queen cells under way."
                    : "Queenless for \(hive.daysQueenless) days, with no replacement being raised.",
                suggestion: hive.canStillRearAQueen
                    ? "There is still young brood to raise a queen from."
                    : "There is no young brood left to raise a queen from."
            ))
        } else if !hive.genetics.isProperlyMated {
            alerts.append(ColonyAlert(
                kind: .queenFailing,
                severity: .critical,
                title: "Drone-Laying Queen",
                detail: "The queen never mated properly and lays only drones.",
                suggestion: "The colony will try to supersede her come spring."
            ))
        }

        if hive.resources.edibleEnergy < config.layingEnergyThreshold * 2 {
            alerts.append(ColonyAlert(
                kind: .starving,
                severity: .critical,
                title: "Starving",
                detail: "Stores are nearly gone.",
                suggestion: "Photograph flowers close to the hive."
            ))
        }

        if season == .autumn, !hive.isWinterReady {
            let shortfall = hive.winterStoresRequired - hive.resources.edibleEnergy
            alerts.append(ColonyAlert(
                kind: .winterStoresLow,
                severity: .warning,
                title: "Winter Stores Short",
                detail: String(
                    format: "%.0f short of the %.0f needed to overwinter.",
                    max(0, shortfall), hive.winterStoresRequired
                ),
                suggestion: "Late-blooming flowers are worth far more than their yield suggests."
            ))
        }

        if let (pathogen, level) = hive.pathogens.dominant, level > 0.25 {
            alerts.append(ColonyAlert(
                kind: .disease,
                severity: level > config.criticalInfectionLevel ? .critical : .warning,
                title: pathogen.displayName,
                detail: String(format: "Infection at %.0f%%.", level * 100),
                suggestion: pathogen.respondsToHygiene
                    ? "Hygienic bees will work at clearing it."
                    : nil
            ))
        }

        let recentAttacks = world.attackHistory.filter { clock.day - $0.day <= 7 }
        if recentAttacks.count >= 2 {
            alerts.append(ColonyAlert(
                kind: .underAttack,
                severity: .warning,
                title: "Under Attack",
                detail: "\(recentAttacks.count) raids in the past week.",
                suggestion: "A better-defended site would hold them off."
            ))
        }

        if hive.broodCount > 0 {
            let deviation = hive.temperatureCelsius - config.targetTemperature
            if deviation < -config.safeTemperatureBand {
                alerts.append(ColonyAlert(
                    kind: .tooCold,
                    severity: .warning,
                    title: "Brood Nest Too Cold",
                    detail: String(format: "%.1f°C, against a target of %.0f°C.",
                                   hive.temperatureCelsius, config.targetTemperature),
                    suggestion: "The colony burns honey to keep warm; it may be short of fuel."
                ))
            } else if deviation > config.safeTemperatureBand {
                alerts.append(ColonyAlert(
                    kind: .tooHot,
                    severity: .warning,
                    title: "Brood Nest Too Hot",
                    detail: String(format: "%.1f°C, against a target of %.0f°C.",
                                   hive.temperatureCelsius, config.targetTemperature),
                    suggestion: "Fanning bees need water to cool the nest."
                ))
            }
        }

        let bloomingPatches = world.patches.filter {
            $0.isInBloom(during: season)
                && !$0.isDepleted
                && $0.isWithinRange
                && !$0.hasFaded(onDay: clock.day, config: config)
        }
        if bloomingPatches.isEmpty, season != .winter, hive.count(performing: .foragingBee) > 0 {
            alerts.append(ColonyAlert(
                kind: .noForage,
                severity: .warning,
                title: "Nothing to Forage",
                detail: world.patches.isEmpty
                    ? "You have not photographed any flowers yet."
                    : "Nothing you have found is in bloom and in range right now.",
                suggestion: "Photograph flowers that bloom in \(season.displayName.lowercased())."
            ))
        }

        if hive.comb.queenCells.contains(where: { $0.purpose == .swarm }) {
            alerts.append(ColonyAlert(
                kind: .swarmPreparing,
                severity: .warning,
                title: "Preparing to Swarm",
                detail: "The nest is crowded and the colony is raising swarm cells.",
                suggestion: "Around half the workforce will leave with the old queen."
            ))
        } else if hive.combOccupancy > 0.9 {
            alerts.append(ColonyAlert(
                kind: .crowded,
                severity: .notable,
                title: "Nest Is Full",
                detail: "Almost every cell is occupied.",
                suggestion: hive.comb.canExpand
                    ? "The colony will draw more comb during a flow."
                    : "The cavity is full. A larger site would let it grow."
            ))
        }

        return alerts.sorted { $0.severity > $1.severity }
    }
}
