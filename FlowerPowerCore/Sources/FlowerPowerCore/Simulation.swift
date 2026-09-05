//
//  Simulation.swift
//  FlowerPowerCore
//
//  The orchestrator. Owns the world, the clock and the random stream, and runs
//  the system pipeline once per simulated hour.
//
//  Two properties matter more than anything else here:
//
//  1. Determinism. Given the same seed and the same inputs, the simulation
//     produces byte-identical results. Offline catch-up therefore yields
//     exactly what live play would have, and a save file resumes without drift.
//  2. Time independence. The engine never relies on a running timer. It is
//     handed a `Date` and computes what should have happened — so it works the
//     same on a foregrounded phone, a watch background refresh, or a cold
//     launch after a week away.
//

import Foundation

public struct Simulation: Codable, Equatable, Sendable {

    /// Settable within the module so tests can arrange preconditions directly;
    /// read-only to consumers, who must go through the player-action methods.
    public internal(set) var world: World
    public internal(set) var clock: SimClock
    public var config: SimulationConfig

    private var rng: SeededRandom
    private var ids: IDGenerator

    // MARK: - Construction

    public init(
        world: World,
        clock: SimClock,
        config: SimulationConfig = .standard,
        seed: UInt64 = 0x5EED_B335,
        ids: IDGenerator = IDGenerator()
    ) {
        self.world = world
        self.clock = clock
        self.config = config
        self.rng = SeededRandom(seed: seed)
        self.ids = ids
    }

    /// Starts a fresh game: a founding colony at the given site, with no forage
    /// until the player photographs some.
    ///
    /// - Parameter inheriting: flowers carried over from a previous colony.
    ///   When a colony dies the player keeps their garden. Those are
    ///   photographs they went out and took, of real places, and confiscating
    ///   them because a queen failed to mate would punish the wrong thing
    ///   entirely — it would also delete the record the map and the garden are
    ///   built from. The flowers are still growing where they always were; it
    ///   is the bees that are gone.
    ///
    ///   They are re-registered rather than copied, so they take fresh
    ///   identifiers from this simulation's generator. Reusing the old ones
    ///   would collide with the new colony's bees, which draw from the same
    ///   counter.
    public static func newGame(
        at location: HiveLocation,
        startingAt date: Date,
        config: SimulationConfig = .standard,
        seed: UInt64 = 0x5EED_B335,
        inheriting patches: [FlowerPatch] = []
    ) -> Simulation {
        var ids = IDGenerator()
        var rng = SeededRandom(seed: seed)

        let hive = Hive.newColony(at: location, ids: &ids)
        let weather = Weather.next(after: Weather(), season: .spring, rng: &rng)

        var simulation = Simulation(
            world: World(hive: hive, weather: weather),
            clock: SimClock(epoch: date),
            config: config,
            seed: seed,
            ids: ids
        )

        for patch in patches {
            simulation.registerPhotograph(
                photoLocalIdentifier: patch.photoLocalIdentifier,
                species: patch.species,
                confidence: patch.identificationConfidence,
                coordinate: patch.coordinate,
                takenAt: patch.discoveredAt,
                // Coordinates are resolved against the *new* hive, which may
                // be somewhere else entirely; only fall back to the stored
                // distance when there is nothing to resolve against.
                distanceMetres: patch.coordinate == nil ? patch.distanceMetres : nil
            )
        }

        return simulation
    }

    // MARK: - The pipeline

    /// Order is deliberate and load-bearing.
    ///
    /// Weather first, because everything downstream depends on whether the bees
    /// can fly. Foraging before processing, so nectar gathered this tick can be
    /// ripened in it. Thermoregulation before nutrition, so the honey burned
    /// keeping warm is gone before anyone sits down to eat — which is what makes
    /// a cold snap during a dearth genuinely dangerous. Status last, so it
    /// observes the finished state.
    private static let pipeline: [any SimulationSystem] = [
        WeatherSystem(),
        PatchSystem(),
        ForagingSystem(),
        ProcessingSystem(),
        ConstructionSystem(),
        ThermoregulationSystem(),
        NutritionSystem(),
        PheromoneSystem(),
        SpoilageSystem(),
        PropolisSystem(),
        BroodSystem(),
        DiseaseSystem(),
        QueenSystem(),
        SwarmSystem(),
        ThreatSystem(),
        PropolisSystem(),
        ColonyStatusSystem()
    ]

    public static var systemNames: [String] { pipeline.map(\.name) }

    // MARK: - Convenience accessors

    public var hive: Hive { world.hive }

    /// Days of backlog a single catch-up will simulate. Time beyond this is
    /// skipped rather than lived through, so it is the length of absence the
    /// game can represent honestly. See `SimClock.maxCatchUpDays`.
    public var catchUpCeilingDays: Int {
        get { clock.maxCatchUpDays }
        set { clock.maxCatchUpDays = max(1, newValue) }
    }

    public var patches: [FlowerPatch] { world.patches }
    public var weather: Weather { world.weather }
    public var season: Season { Season(day: clock.day) }
    public var day: Int { clock.day }

    // MARK: - Driving the clock

    /// Catches the simulation up to `date`. Safe to call on every launch, on
    /// foreground, and from a watch background refresh.
    @discardableResult
    public mutating func advance(to date: Date) -> CatchUpReport {
        var report = CatchUpReport()
        let ticks = clock.pendingTicks(at: date)
        let startDay = clock.day

        for _ in 0..<ticks {
            for event in step() {
                report.record(event)
            }
        }

        report.ticksSimulated = ticks
        report.daysSimulated = clock.day - startDay

        // If the backlog exceeded the catch-up ceiling, jump the clock forward
        // so the colony does not stay permanently behind real time.
        clock.resynchronize(to: date)
        return report
    }

    /// One simulated hour.
    @discardableResult
    public mutating func step() -> [SimEvent] {
        var context = TickContext(clock: clock, config: config, rng: rng, ids: ids)

        for system in Self.pipeline {
            system.update(&world, &context)
        }

        // Deterministic state lives on the simulation, never inside a system.
        rng = context.rng
        ids = context.ids

        clock.commitTick()
        return context.events
    }

    /// Runs a whole simulated day. Useful for tests and for balance sweeps.
    @discardableResult
    public mutating func stepDay() -> [SimEvent] {
        var events: [SimEvent] = []
        for _ in 0..<SimClock.ticksPerDay {
            events += step()
        }
        return events
    }

    // MARK: - Player actions

    /// Registers a photographed flower as a new forage patch. Distance is
    /// resolved against the hive if both have coordinates.
    /// - Parameter distanceMetres: overrides the distance that would otherwise
    ///   be derived from the coordinates. Needed when a photo carries no
    ///   location — the player can still tell us roughly how far it was.
    @discardableResult
    public mutating func registerPhotograph(
        photoLocalIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        coordinate: GeoPoint?,
        takenAt: Date,
        distanceMetres: Double? = nil
    ) -> FlowerPatch {
        let distance: Double
        if let distanceMetres {
            distance = distanceMetres
        } else if let coordinate, let hiveCoordinate = world.hive.location.coordinate {
            distance = coordinate.distance(to: hiveCoordinate)
        } else {
            distance = FlowerPatch.nominalDistance
        }

        let patch = FlowerPatch(
            id: ids.next(),
            photoLocalIdentifier: photoLocalIdentifier,
            species: species,
            identificationConfidence: confidence,
            coordinate: coordinate,
            distanceMetres: distance,
            discoveredAt: takenAt,
            registeredOnDay: clock.day
        )

        world.patches.append(patch)
        return patch
    }

    /// Attaches a species to a patch once classification finishes, which may
    /// well be after the patch was registered.
    public mutating func identifyPatch(
        _ id: EntityID,
        as species: FlowerSpecies,
        confidence: Double
    ) {
        guard let index = world.patches.firstIndex(where: { $0.id == id }) else { return }

        let existing = world.patches[index]
        // Rebuild the patch so capacity picks up the new species, preserving
        // how much of it the bees have already worked.
        let workedNectar = existing.nectarCapacity - existing.remainingNectar
        let workedPollen = existing.pollenCapacity - existing.remainingPollen

        var replacement = FlowerPatch(
            id: existing.id,
            photoLocalIdentifier: existing.photoLocalIdentifier,
            species: species,
            identificationConfidence: confidence,
            coordinate: existing.coordinate,
            distanceMetres: existing.distanceMetres,
            discoveredAt: existing.discoveredAt
        )
        replacement.remainingNectar = max(0, replacement.nectarCapacity - workedNectar)
        replacement.remainingPollen = max(0, replacement.pollenCapacity - workedPollen)

        world.patches[index] = replacement
    }

    /// Corrects a patch's location after the fact — when a photo carried no
    /// EXIF, or the player pins it on the map themselves.
    public mutating func setPatchLocation(
        _ id: EntityID,
        coordinate: GeoPoint?,
        distanceMetres: Double? = nil
    ) {
        guard let index = world.patches.firstIndex(where: { $0.id == id }) else { return }

        world.patches[index].coordinate = coordinate

        if let distanceMetres {
            world.patches[index].distanceMetres = max(0, distanceMetres)
        } else if let coordinate, let hiveCoordinate = world.hive.location.coordinate {
            world.patches[index].distanceMetres = coordinate.distance(to: hiveCoordinate)
        }
    }

    /// Pins a bee to a job, as the design doc's job sliders require.
    public mutating func assign(_ job: WorkerJob?, to beeID: EntityID) {
        guard let index = world.hive.bees.firstIndex(where: { $0.id == beeID }) else { return }
        world.hive.bees[index].assignedJob = job
    }

    /// Pins every bee capable of `job` to it.
    ///
    /// Deliberately not a slider over a pool of interchangeable workers: a bee
    /// does the work her age and condition allow, so emphasising foraging in a
    /// colony of three-day-olds does nothing at all. The player is nudging a
    /// colony that already knows its business, not commanding it.
    ///
    /// - Returns: how many bees actually took the job up.
    @discardableResult
    public mutating func emphasise(_ job: WorkerJob) -> Int {
        var assigned = 0

        for index in world.hive.bees.indices {
            guard world.hive.bees[index].kind == .worker,
                  world.hive.bees[index].isAdult
            else { continue }

            // Clear any previous pin first, so capability is judged naturally.
            world.hive.bees[index].assignedJob = nil

            if world.hive.bees[index].performs(job) {
                world.hive.bees[index].assignedJob = job
                assigned += 1
            }
        }

        return assigned
    }

    /// Clears every manual job assignment, returning the colony to its natural
    /// age-based division of labour.
    public mutating func clearAllAssignments() {
        for index in world.hive.bees.indices {
            world.hive.bees[index].assignedJob = nil
        }
    }

    /// Moves the colony to a new site, as when the player relocates the hive.
    public mutating func relocate(to location: HiveLocation) {
        world.hive.location = location
        // Distances to every known patch change with the hive.
        for index in world.patches.indices {
            if let patchCoordinate = world.patches[index].coordinate,
               let hiveCoordinate = location.coordinate {
                world.patches[index].distanceMetres = patchCoordinate.distance(to: hiveCoordinate)
            }
        }
    }

    /// Drops patches the bees have stripped and that will not regrow, and
    /// patches whose stand has faded away entirely.
    ///
    /// **The app never calls this, and should not.** A patch is also the
    /// player's photograph, and the garden is a record of flowers they went
    /// out and found. Deleting one because the clover was mown would be
    /// deleting their photo. `PatchSummary.hasFaded` is there so the interface
    /// can show a spent patch as spent instead.
    ///
    /// It exists for the balance tooling and the long-running viability tests,
    /// where hundreds of simulated years would otherwise accumulate patches
    /// nothing will ever fly to again.
    public mutating func pruneDepletedPatches() {
        // Read the season into a local first: touching `self.season` inside the
        // closure would overlap the exclusive access to `world.patches`.
        let currentSeason = season
        let day = clock.day
        let config = self.config
        world.patches.removeAll {
            ($0.isDepleted && !$0.isInBloom(during: currentSeason))
                || $0.hasFaded(onDay: day, config: config)
        }
    }
}
