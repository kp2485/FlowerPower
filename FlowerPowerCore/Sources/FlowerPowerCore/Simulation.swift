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
        simulation.world.lineage.found(onDay: 0, patrilines: hive.genetics.patrilines)

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
        PostureSystem(),
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
        ColonyStatusSystem(),
        LineageSystem()
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

        // The almanac is written from what happened, after everything has.
        world.almanac.chronicle(
            context.events,
            day: clock.day,
            honey: world.hive.resources[.honey],
            lineage: world.lineage
        )

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

    /// Takes in a flower somebody else photographed and sent.
    ///
    /// The recipient gets a real patch their bees can work, the same size as
    /// one they photographed themselves. A patch of clover is a patch of
    /// clover; somebody went outside and found it, and that it was not the
    /// recipient does not change what is in the flower. See
    /// `SimulationConfig.sharedPatchYield` for the penalty that used to be
    /// here and the measurement that removed it.
    ///
    /// - Parameters:
    ///   - shareID: the sender's identifier for this flower. Importing the
    ///     same one twice does nothing and returns `nil`. A share arrives in a
    ///     message that stays in the thread for ever, so the tap that imports
    ///     it can happen any number of times.
    ///   - distanceMetres: how far the recipient's bees must fly. Shares
    ///     usually carry no coordinate — see `FlowerShare` on why sending one
    ///     is a privacy decision — so this is normally the nominal distance
    ///     rather than anything derived from where the photograph was taken.
    /// - Returns: the new patch, or `nil` if this flower was already imported.
    @discardableResult
    public mutating func importSharedFlower(
        shareID: String,
        photoLocalIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        coordinate: GeoPoint?,
        takenAt: Date,
        sharedBy: String?,
        distanceMetres: Double? = nil
    ) -> FlowerPatch? {
        guard !world.importedShares.contains(shareID) else { return nil }

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
            registeredOnDay: clock.day,
            origin: .shared,
            sharedBy: sharedBy,
            capacityScale: config.sharedPatchYield
        )

        world.patches.append(patch)
        world.importedShares.insert(shareID)
        return patch
    }

    /// Whether this flower has already been taken in, so the interface can say
    /// so instead of appearing to do nothing.
    public func hasImported(shareID: String) -> Bool {
        world.importedShares.contains(shareID)
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

    /// Moves the colony to a new site.
    ///
    /// A wild colony cannot move house; it can only abscond, and this is
    /// that. The adults go, and nothing else: the comb, the stores and every
    /// larva stay in the old cavity. The bees arrive as a swarm does, with
    /// what honey they could carry in their crops. Relocation used to move
    /// everything, which no colony on earth can do, and it made a hard
    /// decision free.
    public mutating func relocate(to location: HiveLocation) {
        let adults = world.hive.bees.filter(\.isAdult)
        let carried = min(
            world.hive.resources[.honey],
            Double(adults.count) * config.honeyCarriedPerSwarmBee
        )

        let lost = world.hive.bees.count - adults.count
        world.hive.bees = adults
        world.hive.resources = ResourcePool()
        world.hive.resources.add(carried, of: .honey)
        world.hive.comb = Comb(workerCells: 0, droneCells: 0, capacity: location.type.maximumCells)
        world.hive.propolisEnvelope = 0
        world.hive.location = location
        world.activeThreat = nil
        world.pendingSwarm = nil
        world.entranceSealed = false
        world.posture = .instinct
        world.postureUntilDay = nil

        // Distances to every known patch change with the hive.
        for index in world.patches.indices {
            if let patchCoordinate = world.patches[index].coordinate,
               let hiveCoordinate = location.coordinate {
                world.patches[index].distanceMetres = patchCoordinate.distance(to: hiveCoordinate)
            }
        }

        world.almanac.chronicle(
            [.absconded(beesLost: lost)], day: clock.day,
            honey: carried, lineage: world.lineage
        )
    }

    // MARK: - Decisions

    /// Adopts a stance for a number of days. Instinct clears it.
    public mutating func adoptPosture(_ posture: HivePosture, forDays days: Int = 3) {
        world.posture = posture
        world.postureUntilDay = posture == .instinct ? nil : clock.day + max(1, days)
        world.almanac.chronicle(
            [.postureAdopted(posture)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
    }

    /// Answers a siege. The posture holds until the threat resolves.
    public mutating func respond(to threat: ActiveThreat, with posture: HivePosture) {
        guard world.activeThreat == threat else { return }
        adoptPosture(posture, forDays: max(1, threat.resolvesOnDay - clock.day + 1))
    }

    /// Tries to talk the colony out of swarming. Reduces the chance; does
    /// not remove it.
    public mutating func discourageSwarm() {
        guard var pending = world.pendingSwarm else { return }
        pending.discouraged = true
        world.pendingSwarm = pending
        adoptPosture(.makeRoom, forDays: max(1, pending.departsOnDay - clock.day + 1))
    }

    /// The autumn decision: seal the entrance for winter, or leave it open.
    /// Nil hands it back to instinct.
    public mutating func decideEntrance(sealed: Bool?) {
        world.entranceDecision = sealed
        guard let sealed, season == .autumn else { return }
        if sealed, !world.entranceSealed,
           world.hive.resources[.propolis] >= config.entranceSealPropolis {
            world.hive.resources.drain(config.entranceSealPropolis, of: .propolis)
            world.entranceSealed = true
        } else if !sealed, world.entranceSealed {
            world.entranceSealed = false
        }
        world.almanac.chronicle(
            [.entranceSealed(world.entranceSealed)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
    }

    /// Honey the player could take without touching what the colony needs.
    ///
    /// In autumn that is what exceeds the winter requirement; the rest of the
    /// year it is what exceeds the working reserve. Never negative.
    public var harvestableHoney: Double {
        let honey = world.hive.resources[.honey]
        let keep: Double
        switch season {
        case .autumn, .winter:
            keep = world.hive.winterStoresRequired * config.winterProvisioningMargin
        case .spring, .summer:
            keep = max(
                config.layingEnergyThreshold,
                Double(world.hive.adultCount) * config.layingReservePerBee
            ) * 2
        }
        return max(0, honey - keep)
    }

    /// Takes honey. Returns what was actually taken, which is capped at what
    /// the colony can spare — the player is trusted with the decision, not
    /// with the colony's winter.
    @discardableResult
    public mutating func takeHoney(_ units: Double) -> Double {
        let taken = world.hive.resources.drain(min(units, harvestableHoney), of: .honey)
        guard taken > 0 else { return 0 }
        world.honeyTaken += taken
        world.almanac.chronicle(
            [.honeyTaken(taken)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
        return taken
    }

    public mutating func nameQueen(_ number: Int, _ name: String?) {
        world.lineage.name(number, name)
    }

    /// A new colony made from the swarm that just left this one.
    ///
    /// The old queen, the bees who went with her, and the honey in their
    /// crops, at a site of the player's choosing. Nothing else: no comb, no
    /// stores, no brood. The garden comes too. This is what following the
    /// swarm means, and it is the same starting position every real swarm has.
    public func followingSwarm(
        to location: HiveLocation,
        startingAt date: Date,
        seed: UInt64
    ) -> Simulation? {
        guard let swarm = world.lastSwarm else { return nil }
        return Simulation.newGame(
            fromSwarm: swarm,
            at: location,
            startingAt: date,
            config: config,
            seed: seed,
            inheriting: world.patches,
            generation: world.lineage.generation + 1
        )
    }

    /// Builds a colony from a swarm — one that left this player's colony, or
    /// one somebody sent them.
    public static func newGame(
        fromSwarm swarm: DepartedSwarm,
        at location: HiveLocation,
        startingAt date: Date,
        config: SimulationConfig = .standard,
        seed: UInt64,
        inheriting patches: [FlowerPatch] = [],
        generation: Int = 1
    ) -> Simulation {
        var simulation = newGame(
            at: location, startingAt: date, config: config,
            seed: seed, inheriting: patches
        )

        // The swarm's bees take fresh identifiers from this simulation.
        var bees: [Bee] = []
        var queen = swarm.queen
        queen = Bee(
            id: simulation.ids.next(), kind: .queen, stage: .adult,
            daysInStage: queen.daysInStage, patriline: queen.patriline,
            vitality: queen.vitality, wear: queen.wear
        )
        bees.append(queen)
        for worker in swarm.workers {
            bees.append(Bee(
                id: simulation.ids.next(), kind: .worker, stage: .adult,
                daysInStage: worker.daysInStage, patriline: worker.patriline,
                vitality: worker.vitality, wear: worker.wear,
                physiology: worker.physiology
            ))
        }

        simulation.world.hive.bees = bees
        simulation.world.hive.genetics = swarm.genetics
        simulation.world.hive.queenIsMated = true
        simulation.world.hive.resources = ResourcePool()
        simulation.world.hive.resources.add(swarm.honeyCarried, of: .honey)
        simulation.world.hive.comb = Comb(
            workerCells: 0, droneCells: 0, capacity: location.type.maximumCells
        )

        // Her number comes with her.
        let carried = swarm.queenNumber.map { number in
            QueenRecord(
                number: number, motherNumber: nil, emergedOnDay: 0,
                matedOnDay: 0, patrilines: swarm.genetics.patrilines
            )
        }
        simulation.world.lineage = Lineage.continuing(from: carried, generation: generation)
        return simulation
    }

    /// Clears the record of the last swarm once the player has decided.
    public mutating func forgetLastSwarm() {
        world.lastSwarm = nil
    }

    /// The real instant a number of simulated days from now begins, under
    /// the seasonal clock.
    public func date(afterSimulatedDays days: Int) -> Date {
        clock.date(atTick: clock.tick + days * SimClock.ticksPerDay)
    }

    /// Seasonal clock speed. See `SimClock.winterSpeed`.
    public var winterSpeed: Double {
        get { clock.winterSpeed }
        set { clock.winterSpeed = max(0.25, newValue) }
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
