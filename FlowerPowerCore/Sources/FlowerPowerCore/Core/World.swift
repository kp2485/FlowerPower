//
//  World.swift
//  FlowerPowerCore
//
//  All mutable simulation state in one place. Systems read and write this and
//  nothing else, which is what keeps them independently testable.
//

import Foundation

public struct World: Codable, Equatable, Sendable {

    public var hive: Hive
    public var patches: [FlowerPatch]
    public var weather: Weather

    /// Recent attacks, newest last. Trimmed so save files do not grow forever.
    public var attackHistory: [AttackRecord]

    /// Rolling record of *completed* days' nectar intake, used to detect a flow
    /// or a dearth — the colony behaves very differently under each.
    public var recentNectarIntake: [Double]

    /// Nectar gathered so far today, folded into the window at the day boundary.
    public var todayNectarIntake: Double

    /// Identifiers of flowers other people have sent, so the same one cannot
    /// be imported twice.
    ///
    /// Kept here rather than inferred from `patches` because a patch can be
    /// pruned or a colony started afresh, and neither of those should make an
    /// old share importable again — a shared flower arrives in a message that
    /// stays in the thread for ever and can be tapped any number of times.
    public var importedShares: Set<String> = []

    // MARK: Decisions

    /// The colony's stance, and how long it holds. See `HivePosture`.
    public var posture: HivePosture = .instinct
    public var postureUntilDay: Int?

    /// A siege in progress, during which the player may answer.
    public var activeThreat: ActiveThreat?

    /// A swarm on its way, during which the player may answer.
    public var pendingSwarm: PendingSwarm?

    /// The last swarm to leave, kept so the player may go with it.
    public var lastSwarm: DepartedSwarm?

    // MARK: The world outside

    /// The country around the nest, or `nil` for a colony founded before there
    /// was any.
    ///
    /// Optional rather than defaulted so that "this save predates the world"
    /// is a state the engine can see and act on, which is what
    /// `Simulation.adoptTerrainIfMissing()` is for. Once it is set the garden
    /// has cells in it and patches have somewhere to be; while it is nil every
    /// patch stands at whatever distance it was given, exactly as before.
    public var terrain: Terrain?

    /// A scouting party in the field, or nil when everybody is foraging.
    ///
    /// The one thing about the world the colony carries in its save. Where a
    /// chunk is known is `Terrain.discovered`; where the bees *are* is here,
    /// because it is a state of the colony and it has to survive being put
    /// down mid-flight.
    public var scoutingParty: ScoutingParty?

    /// Whether some of today's foragers went wandering instead of working.
    ///
    /// Transient: `ExplorationSystem` sets it at the day boundary and clears
    /// it at the next one, and `ForagingSystem` is the only thing that reads
    /// it. Saved anyway, because a save taken mid-day that came back with the
    /// flag cleared would give the colony a few free foraging hours.
    public var exploringToday = false

    /// Whether the entrance is propolised down for winter.
    public var entranceSealed = false
    /// The player's word on it for this autumn, or nil for instinct.
    public var entranceDecision: Bool?

    // MARK: Record

    public var lineage = Lineage()
    public var almanac = Almanac()
    /// The colony's numbers, one reading a day. See `History.swift`.
    public var history = ColonyHistory()
    /// Honey the player has taken, over the life of the colony.
    public var honeyTaken: Double = 0
    /// What this colony has done for the first time. See `Milestones` for why
    /// they belong to the colony rather than to the player.
    public var milestones = Milestones()

    public init(
        hive: Hive,
        patches: [FlowerPatch] = [],
        weather: Weather = Weather(),
        attackHistory: [AttackRecord] = [],
        recentNectarIntake: [Double] = [],
        todayNectarIntake: Double = 0
    ) {
        self.hive = hive
        self.patches = patches
        self.weather = weather
        self.attackHistory = attackHistory
        self.recentNectarIntake = recentNectarIntake
        self.todayNectarIntake = todayNectarIntake
    }

    /// Decoded by hand for one reason: Swift's synthesised decoder ignores
    /// property defaults and throws on a missing key, so adding
    /// `importedShares` would have made every save written before sharing
    /// existed undecodable. `GameStore.load` then treated an unreadable save as
    /// no save, so that would have silently deleted people's colonies; it
    /// keeps the file aside now, but a colony the player cannot open is still
    /// lost to them.
    ///
    /// **The rule, for every type in the save:** a key added after the first
    /// save is decoded with `decodeIfPresent` and a default. A synthesised
    /// decoder is safe only while every one of its keys has been in every save
    /// ever written, and `SaveCompatibilityTests` fails the day one is added
    /// that has not.
    ///
    /// Only `init(from:)` is written out; the encoder is still synthesised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hive = try container.decode(Hive.self, forKey: .hive)
        patches = try container.decode([FlowerPatch].self, forKey: .patches)
        weather = try container.decode(Weather.self, forKey: .weather)
        attackHistory = try container.decode([AttackRecord].self, forKey: .attackHistory)
        recentNectarIntake = try container.decode([Double].self, forKey: .recentNectarIntake)
        todayNectarIntake = try container.decode(Double.self, forKey: .todayNectarIntake)
        importedShares = try container.decodeIfPresent(
            Set<String>.self, forKey: .importedShares
        ) ?? []

        // Everything below arrived with the decision and record features, and
        // every save from before then must still open.
        posture = try container.decodeIfPresent(HivePosture.self, forKey: .posture) ?? .instinct
        postureUntilDay = try container.decodeIfPresent(Int.self, forKey: .postureUntilDay)
        activeThreat = try container.decodeIfPresent(ActiveThreat.self, forKey: .activeThreat)
        pendingSwarm = try container.decodeIfPresent(PendingSwarm.self, forKey: .pendingSwarm)
        lastSwarm = try container.decodeIfPresent(DepartedSwarm.self, forKey: .lastSwarm)
        entranceSealed = try container.decodeIfPresent(Bool.self, forKey: .entranceSealed) ?? false
        entranceDecision = try container.decodeIfPresent(Bool.self, forKey: .entranceDecision)
        lineage = try container.decodeIfPresent(Lineage.self, forKey: .lineage) ?? Lineage()
        almanac = try container.decodeIfPresent(Almanac.self, forKey: .almanac) ?? Almanac()
        honeyTaken = try container.decodeIfPresent(Double.self, forKey: .honeyTaken) ?? 0
        milestones = try container.decodeIfPresent(
            Milestones.self, forKey: .milestones
        ) ?? Milestones()
        history = try container.decodeIfPresent(ColonyHistory.self, forKey: .history)
            ?? ColonyHistory()

        // The world arrived last of all. A save without it opens with no
        // terrain and is given one on load rather than here, because deriving
        // a seed needs the colony's random stream and a `World` cannot see it.
        // See `Simulation.adoptTerrainIfMissing()`.
        terrain = try container.decodeIfPresent(Terrain.self, forKey: .terrain)

        // And the country after it. A save written before scouting existed has
        // nobody out and nobody wandering, which is exactly what these
        // defaults say.
        scoutingParty = try container.decodeIfPresent(
            ScoutingParty.self, forKey: .scoutingParty
        )
        exploringToday = try container.decodeIfPresent(
            Bool.self, forKey: .exploringToday
        ) ?? false
    }

    public static let attackHistoryLimit = 40
    public static let intakeWindow = 7

    /// Mean daily nectar intake over the recent window.
    public var averageNectarIntake: Double {
        guard !recentNectarIntake.isEmpty else { return 0 }
        return recentNectarIntake.reduce(0, +) / Double(recentNectarIntake.count)
    }

    /// A nectar flow: forage arriving faster than the colony consumes it. Real
    /// colonies switch behaviour wholesale — building comb, rearing brood and,
    /// if crowded, preparing to swarm.
    ///
    /// Both thresholds live in `SimulationConfig` because they are expressed
    /// in forage units, and those units were redefined when nectar became
    /// sugar yield derived from real floral traits.
    public func isInFlow(_ config: SimulationConfig) -> Bool {
        averageNectarIntake > Double(hive.adultCount) * config.flowThresholdPerBee
    }

    /// A dearth. Colonies stop rearing brood, evict drones and start robbing.
    public func isInDearth(_ config: SimulationConfig) -> Bool {
        averageNectarIntake < Double(hive.adultCount) * config.dearthThresholdPerBee
    }

    /// Patches actually worth flying to right now.
    public func availablePatches(
        during season: Season,
        onDay day: Int,
        config: SimulationConfig
    ) -> [FlowerPatch] {
        patches.filter {
            $0.isInBloom(during: season)
                && $0.isWithinRange
                && !$0.isDepleted
                && !$0.hasFaded(onDay: day, config: config)
        }
    }

    /// Closes the books on the day just ended and starts a fresh tally.
    mutating func rollOverNectarIntake() {
        recentNectarIntake.append(todayNectarIntake)
        todayNectarIntake = 0
        if recentNectarIntake.count > Self.intakeWindow {
            recentNectarIntake.removeFirst(recentNectarIntake.count - Self.intakeWindow)
        }
    }

    mutating func recordAttack(_ record: AttackRecord) {
        attackHistory.append(record)
        if attackHistory.count > Self.attackHistoryLimit {
            attackHistory.removeFirst(attackHistory.count - Self.attackHistoryLimit)
        }
    }

    // MARK: - Finding the country

    /// Records a chunk as known and plants whatever grows in it.
    ///
    /// The one place a wild patch is ever created. Discovery and registration
    /// are the same act on purpose: a chunk is generated on demand for
    /// drawing, but its *flowers* have state — how much of the stand the bees
    /// have taken, how much has grown back — and state has to live in the save
    /// rather than be re-derived. So the moment a bee reaches a chunk, the
    /// chunk's seeds become patches with ids from the colony's counter, and
    /// from then on they are ordinary patches that happen never to fade.
    ///
    /// **The home chunk grows wild flowers too**, in every cell but the one
    /// the bees live in. Its 37 cells are exactly the three rings of the
    /// garden — a coincidence of both being radius 3 — and the first instinct
    /// was to leave it to the player's plot. Measured, that was wrong by a
    /// long way: it put every wild flower in the game at 800 m or more, where
    /// the distance efficiency is 0.67 and falling, and a colony on wild
    /// forage alone survived its first year eight times in a hundred however
    /// much was growing out there. The country has to start at the doorstep.
    /// The garden takes precedence where the two meet — see
    /// `Simulation.nextFreeGardenCell()`.
    ///
    /// Does nothing at all for a chunk already known, so it is safe to call on
    /// every discovery path.
    ///
    /// - Returns: how many patches were planted.
    @discardableResult
    mutating func discover(
        _ chunk: ChunkCoordinate,
        ids: inout IDGenerator,
        config: SimulationConfig,
        on day: Int,
        at date: Date
    ) -> Int {
        guard var terrain else { return 0 }
        guard !terrain.hasDiscovered(chunk) else { return 0 }

        terrain.discover(chunk)
        self.terrain = terrain

        return plantWildFlowers(of: chunk, ids: &ids, config: config, on: day, at: date)
    }

    /// Creates the patches of an already-discovered chunk.
    ///
    /// Split out from `discover` so that founding — where the seven home
    /// chunks are known before anybody asks — and a change of world seed under
    /// `beesim` can both use it without pretending to discover ground that is
    /// already on the map.
    @discardableResult
    mutating func plantWildFlowers(
        of chunk: ChunkCoordinate,
        ids: inout IDGenerator,
        config: SimulationConfig,
        on day: Int,
        at date: Date
    ) -> Int {
        guard let terrain else { return 0 }

        let biome = terrain.generator.biome(at: chunk)
        var planted = 0

        for seed in terrain.generator.wildPatches(in: chunk, density: config.wildPatchDensity) {
            // Nothing grows in the nest.
            guard seed.cell != HexCoordinate.origin else { continue }

            let distance = seed.cell.metresFromOrigin
            // Past the range there is nothing to work however much grows
            // there, and a patch with a distance efficiency of zero is dead
            // weight in a save that is walked every tick.
            guard distance <= FlowerPatch.maximumForagingRange else { continue }

            patches.append(FlowerPatch(
                id: ids.next(),
                photoLocalIdentifier: FlowerPatch.wildPhotoIdentifier(for: seed.cell),
                species: FlowerCatalogue.species(withID: seed.speciesID),
                // No photograph, so no identification bonus. The bees know
                // perfectly well what it is; the player has not recorded it.
                identificationConfidence: 0,
                distanceMetres: distance,
                discoveredAt: date,
                // Never fades. A hedge is cut and grows back, and there is no
                // photograph of it ageing out. See `FlowerPatch.vigour`.
                registeredOnDay: nil,
                origin: .wild,
                capacityScale: config.wildPatchYield * biome.wildAbundance * seed.variation,
                cell: seed.cell
            ))
            planted += 1
        }

        return planted
    }

    /// Wild patches belonging to chunks that are no longer part of this world.
    ///
    /// Only `beesim --world-seed` and `--biome` ever move the ground out from
    /// under a colony, and when they do the flowers of the old country have to
    /// go with it.
    mutating func removeWildPatches() {
        patches.removeAll(where: \.isWild)
    }
}

/// Foragers sent out to look at the country rather than to work it.
///
/// A record of a commitment with a date on it, in the shape `PendingSwarm` and
/// `ActiveThreat` already take: when they left, when they are due back. What
/// they find is decided on the day they return and not before, so there is
/// nothing here about where they went — the answer is "the ring of rumoured
/// ground", and that ring is derived from the map at the moment they get home.
public struct ScoutingParty: Codable, Equatable, Sendable {

    public let leftOnDay: Int
    public let returnsOnDay: Int

    public init(leftOnDay: Int, returnsOnDay: Int) {
        self.leftOnDay = leftOnDay
        self.returnsOnDay = returnsOnDay
    }

    public func daysRemaining(on day: Int) -> Int { max(0, returnsOnDay - day) }
}
