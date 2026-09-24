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
    ///   entirely — it would also delete the record the garden is built from.
    ///   The flowers are still growing where they always were; it is the bees
    ///   that are gone.
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

        var world = World(hive: hive, weather: weather)
        // The country the colony wakes up in. Its seed is derived from the
        // colony's rather than shared with it, so that two colonies given the
        // same seed find the same ground — which is what makes a `beesim`
        // trial reproducible — while the colony's own random stream stays
        // untouched by anything the generator does.
        world.terrain = Terrain(seed: Self.terrainSeed(from: seed))

        // And what grows in it. A founding swarm's scouts have already been
        // over the home chunk and the six around it, so those six parishes'
        // hedges are on the map before the first bee flies — the home chunk
        // itself grows nothing wild, because its cells are the garden. The
        // patches are created here rather than derived on demand because they
        // have state: how much of the stand has been worked, and how much has
        // grown back. See `World.discover(_:ids:config:on:at:)`.
        for chunk in world.terrain?.discovered ?? [] {
            world.plantWildFlowers(of: chunk, ids: &ids, config: config, on: 0, at: date)
        }

        var simulation = Simulation(
            world: world,
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
                takenAt: patch.discoveredAt,
                // The flowers are where they were; it is the colony that has
                // started again, so each patch keeps the distance it had, and
                // its cell with it. Phase 3 is where following a swarm starts
                // meaning the garden is left behind.
                at: patch.cell,
                distanceMetres: patch.distanceMetres
            )
        }

        return simulation
    }

    /// The world seed that goes with a colony seed.
    ///
    /// Mixed rather than reused, so that the countryside and the colony are
    /// independent: a change to how the colony draws its randomness must not
    /// move the village.
    static func terrainSeed(from seed: UInt64) -> UInt64 {
        var stream = SeededRandom(seed: seed ^ 0x776F_726C_645F_7365)
        return stream.next()
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
        // After foraging and once a day, at the day boundary — which is before
        // any of the day's daylight ticks, so the share it commits is a share
        // the day's foraging never sees.
        ExplorationSystem(),
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
        LineageSystem(),
        // After the lineage, because two of its conditions read the record
        // the lineage system has just written. It reads everything and writes
        // only `world.milestones`, so it cannot move the balance.
        MilestoneSystem(),
        // Absolutely last: it takes a reading of the finished day and writes
        // it to the record. Nothing downstream, nothing random, nothing that
        // any other system can see.
        HistorySystem()
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

    /// The player's flowers: what they photographed, and what was sent them.
    ///
    /// **Not everything the bees work.** Since the country exists, `world`
    /// holds wild stands as patches too, and almost nothing that asks for
    /// "the patches" means those: the garden is a record of photographs, the
    /// collection is built from it, a new colony inherits it, and an archive
    /// exports it. Handing a wild hedge to any of those would turn the ground
    /// into somebody's photograph — `newGame(inheriting:)` would re-register
    /// it as one — so the plain name keeps the plain meaning and the country
    /// has to be asked for by name.
    public var patches: [FlowerPatch] { world.patches.filter { !$0.isWild } }

    /// What grows wild on the ground the colony has found.
    public var wildPatches: [FlowerPatch] { world.patches.filter(\.isWild) }

    /// Everything the bees can fly to, garden and country together. The
    /// engine's own view, and what `ForagingSystem` works from.
    public var allPatches: [FlowerPatch] { world.patches }
    public var weather: Weather { world.weather }
    /// What this colony has done for the first time.
    public var milestones: Milestones { world.milestones }

    /// The day-by-day record, for the charts. Not on the snapshot: a snapshot
    /// is rebuilt on every refresh and two years of samples is not something
    /// to copy twenty times a minute.
    public var history: ColonyHistory { world.history }

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

    /// Registers a photographed flower as a new forage patch.
    ///
    /// - Parameters:
    ///   - cell: where in the garden to put it. Left off, and with a world to
    ///     put it in, the game chooses the first free cell in ring order —
    ///     which is what planting a flower means now that the garden is a
    ///     place. See `nextFreeGardenCell()`.
    ///   - distanceMetres: how far the bees must fly, as an explicit override.
    ///     An explicit distance wins over placement and suppresses it
    ///     entirely, which is how `beesim` holds a whole sweep at one distance
    ///     and why every measured number in `PLAN.md` still reproduces. With
    ///     no world and no distance the patch stands at
    ///     `FlowerPatch.nominalDistance`, exactly as it always has.
    @discardableResult
    public mutating func registerPhotograph(
        photoLocalIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        takenAt: Date,
        at cell: HexCoordinate? = nil,
        distanceMetres: Double? = nil
    ) -> FlowerPatch {
        let placement = placement(preferring: cell, explicitDistance: distanceMetres)

        let patch = FlowerPatch(
            id: ids.next(),
            photoLocalIdentifier: photoLocalIdentifier,
            species: species,
            identificationConfidence: confidence,
            distanceMetres: distanceMetres
                ?? placement?.metresFromOrigin
                ?? FlowerPatch.nominalDistance,
            discoveredAt: takenAt,
            registeredOnDay: clock.day,
            cell: placement
        )

        if let placement { clearWildPatch(at: placement) }
        world.patches.append(patch)
        return patch
    }

    // MARK: Planting

    /// Where a new patch should stand.
    ///
    /// Three cases, and the middle one is the whole of the world's effect on
    /// the existing balance: a caller that names a distance is saying where
    /// the flower is, so the game does not also choose a cell for it.
    private mutating func placement(
        preferring cell: HexCoordinate?,
        explicitDistance: Double?
    ) -> HexCoordinate? {
        if let cell { return cell }
        guard explicitDistance == nil, world.terrain != nil else { return nil }
        return nextFreeGardenCell()
    }

    /// The first cell of the garden nothing is standing in, opening a ring if
    /// every open one is taken.
    ///
    /// Ring order, innermost first: the keystones a player plants early end up
    /// closest to the nest, which is both the best place for them and a
    /// pleasing accident of the order photographs arrive in.
    ///
    /// "Free" means no *unfaded* patch holds it. A patch that has gone over —
    /// the clover mown, the verge built on — is still in the garden as a
    /// record and still shows as spent, but its ground is available again,
    /// which is the whole point of `vigour` reaching zero.
    ///
    /// A full garden opens the next ring rather than refusing the flower.
    /// Turning away a photograph somebody went out and took is the one thing
    /// this must never do.
    private mutating func nextFreeGardenCell() -> HexCoordinate? {
        guard var terrain = world.terrain else { return nil }
        defer { world.terrain = terrain }

        let day = clock.day
        let config = self.config
        var taken = Set<HexCoordinate>()
        for patch in world.patches {
            // A wild stand does not hold a garden cell against a photograph.
            // The country grows right up to the nest — see
            // `World.plantWildFlowers` — and the alternative was a garden that
            // pushed the player's flowers outward to get round a patch of
            // nettles. The nettles are dug up instead; `clearWildPatch(at:)`
            // does it the moment the flower is planted.
            guard !patch.isWild else { continue }
            guard let cell = patch.cell, !patch.hasFaded(onDay: day, config: config) else { continue }
            taken.insert(cell)
        }

        // Walking the rings rather than iterating `taken`: the set is only
        // ever asked about a cell, never iterated, so its hash order cannot
        // reach the answer.
        for cell in terrain.gardenCells where !taken.contains(cell) {
            return cell
        }

        // Every open ring is full. The garden grows.
        let opened = terrain.openNextRing()
        return opened.first
    }

    /// Whether any patch still standing is in this cell.
    ///
    /// Wild stands do not count. They are the ground rather than the garden,
    /// and planting on one clears it.
    public func isCellOccupied(_ cell: HexCoordinate) -> Bool {
        let day = clock.day
        let config = self.config
        return world.patches.contains {
            !$0.isWild && $0.cell == cell && !$0.hasFaded(onDay: day, config: config)
        }
    }

    /// Digs up whatever was growing wild in a cell the player has just planted.
    ///
    /// One patch to a cell is what gives a garden of thirty flowers a shape,
    /// and the shape has to be the player's. Removing it outright rather than
    /// hiding it: the wild stand is regenerable, so it comes back the next
    /// time the ground is planted afresh, and a cell holding two patches would
    /// quietly double the forage there.
    private mutating func clearWildPatch(at cell: HexCoordinate) {
        world.patches.removeAll { $0.isWild && $0.cell == cell }
    }

    /// Moves a patch to a cell, and its distance with it.
    ///
    /// There was no way to move a patch after creation and there has to be
    /// one: the garden is a plot the player arranges, and a flower planted in
    /// the wrong place should be movable rather than re-photographed.
    ///
    /// Refuses a cell another standing patch is already in — one patch to a
    /// cell is what gives a garden of thirty flowers a shape.
    ///
    /// - Returns: whether the patch moved.
    @discardableResult
    public mutating func plant(_ id: EntityID, at cell: HexCoordinate) -> Bool {
        guard let index = world.patches.firstIndex(where: { $0.id == id }) else { return false }
        guard world.patches[index].cell != cell else { return true }
        guard !isCellOccupied(cell) else { return false }

        clearWildPatch(at: cell)
        guard let index = world.patches.firstIndex(where: { $0.id == id }) else { return false }
        world.patches[index].cell = cell
        world.patches[index].distanceMetres = cell.metresFromOrigin
        return true
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
    ///   - distanceMetres: how far the recipient's bees must fly. A share says
    ///     what the flower is and nothing about where it was, so this is
    ///     normally left off and the flower is planted in the recipient's own
    ///     garden — which is the honest reading of a gift, and the same
    ///     placement a photograph gets. See `registerPhotograph`.
    /// - Returns: the new patch, or `nil` if this flower was already imported.
    @discardableResult
    public mutating func importSharedFlower(
        shareID: String,
        photoLocalIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        takenAt: Date,
        sharedBy: String?,
        at cell: HexCoordinate? = nil,
        distanceMetres: Double? = nil
    ) -> FlowerPatch? {
        guard !world.importedShares.contains(shareID) else { return nil }

        let placement = placement(preferring: cell, explicitDistance: distanceMetres)

        let patch = FlowerPatch(
            id: ids.next(),
            photoLocalIdentifier: photoLocalIdentifier,
            species: species,
            identificationConfidence: confidence,
            distanceMetres: distanceMetres
                ?? placement?.metresFromOrigin
                ?? FlowerPatch.nominalDistance,
            discoveredAt: takenAt,
            registeredOnDay: clock.day,
            origin: .shared,
            sharedBy: sharedBy,
            capacityScale: config.sharedPatchYield,
            cell: placement
        )

        if let placement { clearWildPatch(at: placement) }
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
    ///
    /// **Everything the patch already is has to be carried over by hand.**
    /// This rebuilds the patch rather than editing it, because the capacity is
    /// computed in the initialiser from the species — and for a long while the
    /// rebuild quietly dropped `registeredOnDay`, the origin and `sharedBy`.
    /// A patch identified on day 100 was handed a fresh registration day and
    /// so went back to full vigour, having aged not at all; a shared flower
    /// forgot it had been a gift and who sent it. Neither was visible in a
    /// balance run, because `beesim` identifies at the moment of registering.
    /// `WORLD.md` section 9 calls this out as the thing to fix before the
    /// world starts making patches in bulk, which is exactly right: a
    /// generator that plants wild flowers and then names them would have
    /// reset every one of them.
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
            distanceMetres: existing.distanceMetres,
            discoveredAt: existing.discoveredAt,
            // The photograph was taken when it was taken. This is the line
            // that keeps a late identification from making a flower fresh.
            registeredOnDay: existing.registeredOnDay,
            origin: existing.origin,
            sharedBy: existing.sharedBy,
            // A gift is worth what a gift is worth, before and after somebody
            // works out what it was. `sharedPatchYield` is 1.0 today, so this
            // changes no number now; it is here so that the day it is not 1.0,
            // naming a flower does not silently enlarge it.
            capacityScale: existing.origin == .shared ? config.sharedPatchYield : 1,
            cell: existing.cell
        )
        replacement.remainingNectar = max(0, replacement.nectarCapacity - workedNectar)
        replacement.remainingPollen = max(0, replacement.pollenCapacity - workedPollen)

        world.patches[index] = replacement
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

    // MARK: Answering congestion

    /// Cells of room the nest could still be given, beyond what it has.
    ///
    /// Derived rather than stored: the natural cavity is a property of the
    /// site, so how far the nest has already been extended is the difference
    /// between the comb's capacity and that. Relocating resets it, correctly —
    /// a colony that absconds takes nothing with it, least of all the hole it
    /// was living in.
    public var combExtensionRemaining: Int {
        let natural = world.hive.location.type.maximumCells
        let ceiling = natural + Int((Double(natural) * world.hive.location.type.extensionRoom).rounded())
        return max(0, ceiling - world.hive.comb.capacity)
    }

    /// Whether the nest has anywhere to put more comb: either cavity it has
    /// not drawn out yet, or room the site can still be given.
    public var canAddComb: Bool {
        world.hive.comb.freeCapacity > 0 || combExtensionRemaining > 0
    }

    /// The honey one cell of drawn worker comb costs, in wax the bees have to
    /// secrete for it. Roughly seven to one, which is why a colony will not
    /// build speculatively and why drawn comb is the most valuable thing a
    /// beekeeper owns.
    public var honeyPerDrawnCell: Double {
        CellType.worker.waxCost * config.honeyPerWax
    }

    /// Opens the nest up: more cavity, and comb drawn into it there and then,
    /// paid for in honey. Returns the cells actually drawn.
    ///
    /// **Why this draws the comb rather than only making room for it.** The
    /// first version of this method did the obvious thing — raise
    /// `Comb.capacity` and let `ConstructionSystem` fill it — and measurement
    /// said it did nothing at all. Across 60 colonies over two years it never
    /// fired once, and when the trigger was loosened so that it did, swarming
    /// was unmoved.
    ///
    /// The reason is in `Hive.swarmPressure`, which is driven by
    /// `combOccupancy` — cells *used* over cells *drawn*. Empty cavity is not
    /// in that ratio. A congested colony is one that has filled the comb it
    /// has, and it cannot draw more, because drawing comb needs a nectar flow
    /// and spare honey and it has neither to spare. Giving it room it cannot
    /// afford to use changes nothing.
    ///
    /// Which is exactly why beekeepers prize drawn comb over foundation. A
    /// super of foundation on a colony that is about to swarm does not stop it
    /// swarming; a super of drawn comb does, immediately, because the bees can
    /// move into it the same afternoon. So that is what this gives them, and
    /// the honey it costs is the honey the wax would have cost.
    ///
    /// The trade the player is actually offered: about a fifth of a good
    /// year's stores, against half the colony. It is paid now and felt in
    /// November.
    ///
    /// A swarm already gathering is discouraged by it, on the same odds as
    /// `discourageSwarm` — but without that method's `makeRoom` posture, which
    /// holds the foragers back. That is the point of paying in honey.
    @discardableResult
    public mutating func addComb() -> Int {
        let step = max(1, Int((Double(world.hive.location.type.maximumCells)
                               * config.combExtensionStep).rounded()))

        // Never spend the colony into a corner. The same reserve
        // `ConstructionSystem` refuses to build below.
        let spendable = max(0, world.hive.resources[.honey] - combPurchaseReserve)
        let affordable = Int(spendable / honeyPerDrawnCell)

        // Cavity the colony already has but has not drawn out costs nothing to
        // use. A tree does not need hollowing further to hold comb it has room
        // for already — what was stopping the bees was the honey, and that is
        // what is being paid. Only the shortfall comes out of the site's
        // finite extension room.
        let free = world.hive.comb.freeCapacity
        let drawn = min(step, affordable, free + combExtensionRemaining)
        guard drawn > 0 else { return 0 }

        world.hive.comb.extend(by: max(0, drawn - free))
        world.hive.resources.drain(Double(drawn) * honeyPerDrawnCell, of: .honey)
        world.hive.comb.build(drawn, as: .worker)

        if var pending = world.pendingSwarm {
            pending.discouraged = true
            world.pendingSwarm = pending
        }

        world.almanac.chronicle(
            [.combAdded(cells: drawn)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
        return drawn
    }

    /// How many cells the next `addComb` would actually draw.
    ///
    /// The interface used to work this out for itself — a `min` of the step
    /// size and the site's remaining room, written out in the decision card —
    /// which was both wrong (it ignored what the colony could afford, and the
    /// undrawn cavity it would use first) and the same duplicated-logic trap
    /// that put `SimEvent.narration` in a view. The engine knows; it should be
    /// the one asked.
    public var combOnOffer: Int {
        let step = max(1, Int((Double(world.hive.location.type.maximumCells)
                               * config.combExtensionStep).rounded()))
        let spendable = max(0, world.hive.resources[.honey] - combPurchaseReserve)
        let affordable = Int(spendable / honeyPerDrawnCell)
        return max(0, min(step, affordable, world.hive.comb.freeCapacity + combExtensionRemaining))
    }

    /// What the colony will not spend on wax, however much room there is.
    ///
    /// Not `buildHoneyReserve` alone, which is a flat 25 units. That is the
    /// number `ConstructionSystem` refuses to build below, and it is safe there
    /// only because the surplus-income rule already stops a colony converting
    /// its larder — see `waxIncomeShare`. `addComb` has no such rule: it is the
    /// player spending stores on comb directly, and on a flat reserve it was a
    /// way to reproduce, on purpose, the exact bug that the wax fix removed.
    ///
    /// So it scales with the colony, on the same footing as the spring and
    /// summer floor in `broodHeadroom`: what is a comfortable cushion for a
    /// nucleus is less than a day's food for a strong one.
    public var combPurchaseReserve: Double {
        max(
            config.buildHoneyReserve,
            Double(world.hive.adultCount) * config.layingReservePerBee
        )
    }

    /// Whether the colony could pay for an extension right now.
    ///
    /// Separate from `canAddComb`, which is about the site. This is about the
    /// larder, and a player asked to open the nest up in a dearth deserves to
    /// be told that the bees cannot afford the wax.
    public var canAffordComb: Bool {
        max(0, world.hive.resources[.honey] - combPurchaseReserve) >= honeyPerDrawnCell
    }

    /// The best-developed queen cell the colony is holding, of any purpose.
    public var readiestQueenCell: QueenCell? {
        world.hive.comb.queenCells.max { $0.daysDeveloped < $1.daysDeveloped }
    }

    /// Whether the colony could be divided on purpose right now.
    ///
    /// Three things have to be true. There has to be a laying queen to send —
    /// a division *is* the queen leaving. There have to be enough bees that
    /// both halves are still colonies afterwards. And there has to be a queen
    /// cell far enough along to leave behind.
    ///
    /// The last of those is the one that makes the difference between a
    /// mechanic and a trap. See `splitEarliestCellDay`.
    public var canSplit: Bool {
        guard world.hive.hasLayingQueen else { return false }
        guard world.hive.adultWorkerCount >= config.swarmMinimumPopulation else { return false }
        guard let cell = readiestQueenCell else { return false }
        return cell.daysDeveloped >= config.splitEarliestCellDay
    }

    /// Days until the colony could be divided, or nil if it could be now or
    /// could not be at all.
    ///
    /// So the interface can say "in two days" rather than greying a button out
    /// and leaving the player to guess why.
    public var daysUntilSplitPossible: Int? {
        guard world.hive.hasLayingQueen,
              world.hive.adultWorkerCount >= config.swarmMinimumPopulation,
              let cell = readiestQueenCell,
              cell.daysDeveloped < config.splitEarliestCellDay
        else { return nil }
        return config.splitEarliestCellDay - cell.daysDeveloped
    }

    /// Divides the colony deliberately, before it divides itself.
    ///
    /// This is the artificial swarm a beekeeper makes, and it differs from a
    /// swarm in three ways that all favour the colony that stays:
    ///
    /// - **Fewer bees go.** `splitDepartureShare` rather than
    ///   `swarmDepartureShare`.
    /// - **The right bees go.** A swarm takes the oldest workers, which is the
    ///   entire flying workforce, and that is why a swarmed colony stops
    ///   gathering almost completely. Moving the queen instead sends the house
    ///   bees with her: the foragers know where the nest is and stay with it.
    /// - **One cell is kept.** The rest come down, so there is no afterswarm —
    ///   the second and third swarms led by virgin queens that finish what the
    ///   first one started.
    ///
    /// What it does not do is remove the gamble. The colony that stays is
    /// still queenless and still has to get a virgin mated. It simply faces
    /// that with its foragers, its brood and its stores intact.
    ///
    /// The half that leaves becomes `world.lastSwarm`, exactly as a real swarm
    /// does, so the player can follow it, give it to somebody, or let it go.
    @discardableResult
    public mutating func split() -> Bool {
        guard canSplit else { return false }

        let adults = world.hive.bees.indices.filter {
            world.hive.bees[$0].kind == .worker && world.hive.bees[$0].isAdult
        }
        let wanted = max(1, Int(Double(adults.count) * config.splitDepartureShare))

        // Youngest first — the house bees. This is the line that makes a split
        // different from a swarm.
        let leaving = Set(
            adults
                .sorted { world.hive.bees[$0].daysInStage < world.hive.bees[$1].daysInStage }
                .prefix(wanted)
        )
        guard !leaving.isEmpty else { return false }

        guard let queenIndex = world.hive.bees.firstIndex(where: {
            $0.kind == .queen && $0.isAdult
        }) else { return false }

        let workers = world.hive.bees.enumerated()
            .filter { leaving.contains($0.offset) }
            .map(\.element)
        let queen = world.hive.bees[queenIndex]

        world.hive.bees = world.hive.bees.enumerated()
            .filter { !leaving.contains($0.offset) && $0.offset != queenIndex }
            .map(\.element)

        // They go on full crops, like any swarm.
        let carried = world.hive.resources.drain(
            Double(workers.count) * config.honeyCarriedPerSwarmBee, of: .honey
        )

        // The cells are left standing by default, exactly as a swarm leaves
        // them. See `splitQueenCellsKept` for why knocking them down turned
        // out to be the wrong instinct here, even though it is what a
        // beekeeper does.
        if config.splitQueenCellsKept > 0 {
            let keepers = Set(
                world.hive.comb.queenCells
                    .sorted { $0.daysDeveloped > $1.daysDeveloped }
                    .prefix(config.splitQueenCellsKept)
                    .map(\.id)
            )
            world.hive.comb.keepQueenCells(withIDs: keepers)
        }

        world.hive.queenIsMated = false
        world.hive.pheromones.nasonov = 1.0
        world.pendingSwarm = nil

        // Read before ending her, so the swarm carries the number of the queen
        // who actually left rather than whoever the search happens to find.
        let departingNumber = world.lineage.reigning?.number

        // Her reign ends here rather than being reconciled away as "lost" on
        // the next tick. She did not disappear; she was moved.
        world.lineage.end(onDay: clock.day, .leftWithSwarm)

        world.lastSwarm = DepartedSwarm(
            day: clock.day,
            queen: queen,
            workers: workers,
            genetics: world.hive.genetics,
            honeyCarried: carried,
            queenNumber: departingNumber
        )

        world.almanac.chronicle(
            [.colonyDivided(beesLeft: workers.count + 1)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
        return true
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

    /// Honey the player could take without touching what the colony needs:
    /// whatever exceeds the winter requirement, in every season. Never
    /// negative.
    ///
    /// **It used to reserve the winter only in autumn and winter.** In spring
    /// and summer the cap kept back twice the laying threshold and nothing
    /// else, so a player who took what the card offered whenever it offered
    /// it — `beesim --policy harvestEagerly` — lost 200 colonies of 200: the
    /// summer crop was the winter's stores, taken before the colony had the
    /// chance to put them by. Autumn's rule, which reserves the requirement,
    /// was always fine, and on 2026-09-24 it became the rule all year. Taking
    /// honey eagerly is now a price rather than a death sentence; the numbers
    /// are in PLAN.md.
    ///
    /// The requirement scales with the adults, so in summer, with the colony
    /// at its peak, it asks for a reserve sized for a cluster three or four
    /// times the one that will actually winter. That is deliberate: the
    /// alternative is guessing now at a cluster that does not exist yet, and a
    /// guess that is low costs the colony its winter.
    public var harvestableHoney: Double {
        let honey = world.hive.resources[.honey]
        let keep = world.hive.winterStoresRequired * config.winterProvisioningMargin
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

    // MARK: Giving it back

    /// How far below the winter requirement the colony's stores are, in the
    /// same honey-equivalent units `StoresSummary` reports. Zero when it has
    /// enough.
    ///
    /// The same arithmetic as `StoresSummary.winterReadiness` and the
    /// `winterStoresLow` alert, in one place, because three copies of
    /// `requirement - edibleEnergy` is how two of them end up subtly
    /// different.
    public var storesShortfall: Double {
        max(0, world.hive.winterStoresRequired - world.hive.resources.edibleEnergy)
    }

    /// Room for honey in the comb, in units rather than cells.
    ///
    /// The same clamp `ForagingSystem` puts on nectar and pollen intake: what
    /// the colony can take in is what its free cells will hold. A hive with
    /// nowhere to put honey cannot be given any, which is as true of a jar
    /// held over the feeder hole as it is of a nectar flow.
    private var honeyStorageSpace: Double {
        max(0, Double(world.hive.freeCells) * ResourceKind.honey.unitsPerCell)
    }

    /// How much of the banked honey would actually go in if the colony were
    /// fed right now.
    ///
    /// Capped twice over: by what the player has taken and not yet given back,
    /// and by the comb it would have to be stored in. The interface asks this
    /// rather than working it out, for the same reason `combOnOffer` exists —
    /// the engine knows, and a second copy of the arithmetic in a view is a
    /// copy that goes wrong.
    public var feedOnOffer: Double {
        min(world.honeyTaken, honeyStorageSpace)
    }

    /// Whether there is honey banked and somewhere to put it.
    public var canFeed: Bool { feedOnOffer > 0 }

    /// Whether the feeding decision is in front of the player.
    ///
    /// Not a new system and not a new judgement. "Short of stores" is
    /// `Hive.isWinterReady`, which is what `ColonyStatusSystem` warns on and
    /// what the `winterStoresLow` alert is raised from; the cue is that alert
    /// and nothing else. The season gate is the alert's own, widened by one
    /// season: the warning is pitched to arrive while something can still be
    /// done, and once the cluster has formed feeding is the only thing left
    /// that can be.
    public var feedDecisionOpen: Bool {
        guard season == .autumn || season == .winter else { return false }
        return !world.hive.isWinterReady && canFeed
    }

    /// Gives banked honey back to the colony. Returns what actually went in.
    ///
    /// Real beekeepers feed a colony that is short, and a player who took a
    /// crop in a good autumn ought to be able to answer for it in a bad
    /// winter. So this is `takeHoney` run backwards, with the same shape: the
    /// player names an amount, the engine gives them what is really possible,
    /// and what came back is what is reported.
    ///
    /// **Fed honey is honey.** It goes into `resources[.honey]` — the same
    /// pool `NutritionSystem` eats from and `ThermoregulationSystem` burns —
    /// and nothing about it is marked or remembered. A colony cannot tell
    /// where its stores came from and neither can any system here; the only
    /// trace is the almanac's line and the event.
    ///
    /// It is also not free. The bank is `world.honeyTaken`, which is the
    /// game's score, so every unit given back is a unit off it. That is the
    /// whole trade, and it is the reason this is a decision rather than a
    /// button: the honey is the player's, and so is the winter.
    @discardableResult
    public mutating func feed(_ units: Double) -> Double {
        let given = min(max(0, units), feedOnOffer)
        guard given > 0 else { return 0 }

        world.hive.resources.add(given, of: .honey)
        world.honeyTaken -= given

        world.almanac.chronicle(
            [.fed(given)], day: clock.day,
            honey: world.hive.resources[.honey], lineage: world.lineage
        )
        return given
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
            // The player's flowers, not the country's. A swarm takes the
            // garden with it; the hedges stay where they are and the new
            // colony finds its own. Handing `world.patches` over would
            // re-register every wild stand as a photograph.
            inheriting: patches,
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

    // MARK: - The world around the nest

    /// The country this colony lives in, or nil for a save that predates it.
    public var terrain: Terrain? { world.terrain }

    /// The chunk the nest is in, drawn from the seed.
    public var homeChunk: Chunk? { world.terrain?.homeChunk }

    /// Draws a different countryside around the same nest.
    ///
    /// The garden is untouched — its cells belong to the patches, not to the
    /// generator — so this changes what the ground *is* and not what is
    /// planted on it. It exists for `beesim --world-seed`, which needs to put
    /// two hundred colonies on the same ground to see what the ground is
    /// worth, and for a test that wants a particular biome underfoot.
    public mutating func setTerrainSeed(_ seed: UInt64) {
        if world.terrain == nil {
            world.terrain = Terrain(seed: seed)
        } else {
            world.terrain?.seed = seed
        }

        // The old country's hedges go with the old country. Photographed and
        // shared flowers stay: they are the player's, and they are planted in
        // a garden whose cells belong to the nest rather than to the ground.
        world.removeWildPatches()
        replantWildFlowers()
        clearWildPatchesUnderTheGarden()
    }

    /// Puts a particular kind of ground under the nest.
    ///
    /// Scans upward from the terrain seed the colony already has for the first
    /// world whose home chunk is this biome, so two colonies asked for the same
    /// biome still get different neighbours — the biome is fixed and the
    /// country around it is not, which is what makes a survival-by-biome table
    /// a measurement of the biome rather than of one map.
    ///
    /// - Returns: whether such a world was found.
    @discardableResult
    public mutating func setTerrainBiome(_ biome: Biome) -> Bool {
        let start = world.terrain?.seed ?? Self.terrainSeed(from: 0)
        guard let found = WorldGenerator.seed(producing: biome, from: start) else { return false }
        setTerrainSeed(found)
        return true
    }

    /// Creates the wild patches of every chunk already on the map.
    ///
    /// For a change of world seed and for migration. Not for discovery, which
    /// goes through `World.discover(_:ids:config:on:at:)` so that finding
    /// ground and planting it are one act.
    /// Digs up every wild stand standing where a planted flower is.
    ///
    /// For the paths that plant the country in bulk — a change of world seed,
    /// and migration — where doing it flower by flower would mean walking the
    /// patch list once per cell.
    private mutating func clearWildPatchesUnderTheGarden() {
        let plantedCells = Set(world.patches.compactMap { $0.isWild ? nil : $0.cell })
        guard !plantedCells.isEmpty else { return }
        world.patches.removeAll { $0.isWild && $0.cell.map(plantedCells.contains) == true }
    }

    private mutating func replantWildFlowers() {
        guard let discovered = world.terrain?.discovered else { return }
        let date = clock.date(atTick: clock.tick)
        for chunk in discovered {
            world.plantWildFlowers(
                of: chunk, ids: &ids, config: config, on: clock.day, at: date
            )
        }
    }

    /// Gives a colony that has none a world to live in, and plants its flowers
    /// into the garden.
    ///
    /// Every colony founded from now on gets its terrain in `newGame`. This is
    /// for the ones that already exist: a save written before any of this, in
    /// which the flowers are nowhere and every one of them stands at the
    /// nominal 800 m.
    ///
    /// **The seed comes from the colony's own random stream**, read without
    /// consuming it — see `SeededRandom.derivedSeed()`. It has to be
    /// deterministic, because two devices restoring the same save must find
    /// the same countryside; and it has to be particular to the colony, or
    /// every old save in the world would open onto the same village. The
    /// saved RNG state is the one number that is both.
    ///
    /// **The flowers are planted, and that makes the colony better off.** They
    /// move from 800 m to 200 and 400, where the distance efficiency is 0.89
    /// and 0.8 against 0.67, so the same photographs feed the colony a third
    /// better than they did yesterday. That is the honest consequence of a
    /// garden being next to the nest rather than nowhere in particular, and
    /// `WORLD.md` section 10 asks for the baseline to be re-measured rather
    /// than for the effect to be cancelled out.
    ///
    /// Idempotent: a colony that already has terrain is left exactly alone.
    ///
    /// - Returns: whether a world was adopted.
    @discardableResult
    public mutating func adoptTerrainIfMissing() -> Bool {
        guard world.terrain == nil else { return false }

        world.terrain = Terrain(seed: rng.derivedSeed())

        // Ring order, oldest photograph first, so the flowers a player found
        // earliest end up closest to the nest. `world.patches` is already in
        // registration order.
        //
        // A stand that has already gone over is left where it was. It is still
        // in the garden as a record and still shows as spent, but giving it
        // ground would be giving ground to nothing — and the free-cell search
        // ignores faded patches, so two of them would be handed the same cell.
        let day = clock.day
        let config = self.config
        for index in world.patches.indices {
            guard world.patches[index].cell == nil else { continue }
            guard !world.patches[index].hasFaded(onDay: day, config: config) else { continue }
            guard let cell = nextFreeGardenCell() else { break }
            world.patches[index].cell = cell
            world.patches[index].distanceMetres = cell.metresFromOrigin
        }

        // And the country the colony has apparently been living in all along.
        // A migrated save's seven founding chunks come with their hedges, the
        // same as a colony founded today — the alternative is an old colony
        // that can see the map and has nothing on it to work.
        replantWildFlowers()

        // The country grows up to the nest, so a migrated garden lands on wild
        // stands. The garden wins, the same as it does when a flower is planted
        // today.
        clearWildPatchesUnderTheGarden()

        return true
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
            // A wild stand is never pruned. It is the ground rather than a
            // photograph: it comes back every year, and deleting it out of
            // season would quietly empty the countryside over a long run —
            // which is exactly what the balance tooling does, every restock,
            // for hundreds of simulated years.
            guard !$0.isWild else { return false }
            return ($0.isDepleted && !$0.isInBloom(during: currentSeason))
                || $0.hasFaded(onDay: day, config: config)
        }
    }

    // MARK: - Scouts

    /// Whether the "send scouts" decision is in front of the player.
    ///
    /// Three conditions and each one is a reason rather than a gate. A *flow*,
    /// because a tenth of the force is affordable when the nectar is coming in
    /// and is not when it is not — this is the one decision the game offers
    /// while things are going well. *Rumoured ground*, because otherwise there
    /// is nothing to find. And *nobody already out*, because a second party
    /// would be asking the player to pay twice for one answer.
    public var scoutDecisionOpen: Bool {
        guard let terrain = world.terrain else { return false }
        guard world.scoutingParty == nil else { return false }
        guard world.isInFlow(config) else { return false }
        return !terrain.rumoured.isEmpty
    }

    /// Whether a party is in the field.
    public var scoutsOut: Bool { world.scoutingParty != nil }

    /// Days until they are back, or nil when nobody is out.
    public var scoutsDaysRemaining: Int? {
        world.scoutingParty.map { $0.daysRemaining(on: clock.day) }
    }

    /// Ground the dancers have pointed at and nobody has been to.
    public var rumouredChunks: [ChunkCoordinate] { world.terrain?.rumoured ?? [] }

    /// Sends a scouting party: a tenth of the forager force, for three days.
    ///
    /// What they cost is immediate and what they find is not. From today the
    /// colony gathers `scoutShare` less, and on the third day every rumoured
    /// chunk is on the map — see `ExplorationSystem.returnScouts`. Instinct is
    /// to do nothing, as it is for every other decision, and a colony that
    /// never scouts still finds what its foragers reach.
    ///
    /// - Returns: whether they went.
    @discardableResult
    public mutating func sendScouts() -> Bool {
        guard scoutDecisionOpen else { return false }

        world.scoutingParty = ScoutingParty(
            leftOnDay: clock.day,
            returnsOnDay: clock.day + max(1, config.scoutDays)
        )
        return true
    }
}
