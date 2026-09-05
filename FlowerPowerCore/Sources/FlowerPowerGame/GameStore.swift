//
//  GameStore.swift
//  FlowerPowerGame
//
//  The single bridge between the simulation and SwiftUI.
//
//  Everything the interface touches goes through here. Views observe the
//  published snapshot and never see `Simulation`, `Hive` or `World` — which
//  keeps the engine free of UI concerns and means the whole store can be
//  driven from a test or a preview with no camera, no photo library and no
//  clock running.
//

import Foundation
import Observation
import FlowerPowerCore

@Observable
@MainActor
public final class GameStore {

    // MARK: - Published state

    /// What the interface renders. Replaced wholesale after every advance.
    public private(set) var snapshot: ColonySnapshot

    /// What happened while the player was away, shown once and then cleared.
    public private(set) var pendingReport: CatchUpReport?

    public private(set) var isBusy = false
    public private(set) var lastError: String?

    // MARK: - Private state

    private var simulation: Simulation
    private let persistence: GamePersisting
    private let clock: () -> Date

    /// Drives the live view while the app is in the foreground. The simulation
    /// itself never depends on this — it is purely a refresh trigger.
    private var ticker: Task<Void, Never>?

    // MARK: - Lifecycle

    public init(
        simulation: Simulation,
        persistence: GamePersisting = GamePersistence(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.simulation = simulation
        self.persistence = persistence
        self.clock = clock
        self.snapshot = simulation.snapshot()
    }

    /// Loads a saved game, or starts a new one at the given site.
    public static func load(
        persistence: GamePersisting = GamePersistence(),
        defaultSite: HiveLocation = HiveLocation(type: .livingTreeCavity),
        clock: @escaping () -> Date = Date.init
    ) -> GameStore {
        if let saved = try? persistence.load() {
            return GameStore(simulation: saved, persistence: persistence, clock: clock)
        }

        let fresh = Simulation.newGame(
            at: defaultSite,
            startingAt: clock(),
            seed: UInt64.random(in: 1...UInt64.max)
        )
        return GameStore(simulation: fresh, persistence: persistence, clock: clock)
    }

    // MARK: - Advancing time

    /// Brings the colony up to date. Safe to call on launch, on foreground, and
    /// as often as you like — the engine works out how much time has passed.
    public func catchUp() {
        // Whether the colony was already gone before this catch-up. A player
        // returning to a colony that died last week should not be handed a
        // fresh report about the week of nothing that followed; they should be
        // shown the death once, and then the way to start again.
        let wasCollapsed = isCollapsed

        let report = simulation.advance(to: clock())
        snapshot = simulation.snapshot()

        if !wasCollapsed, !report.isEmpty, report.daysSimulated >= 1 {
            pendingReport = report
        }

        if isCollapsed { stopLiveUpdates() }

        save()
    }

    /// Whether there is still a colony to play. The interface swaps to
    /// offering a fresh start on this.
    public var isCollapsed: Bool { !snapshot.status.isAlive }

    public func dismissReport() {
        pendingReport = nil
    }

    /// Starts refreshing the view while the app is visible.
    public func startLiveUpdates(interval: Duration = .seconds(20)) {
        stopLiveUpdates()
        // Nothing left to refresh, and a ticker on a dead colony would keep
        // the phone awake to recompute the same empty nest for ever.
        guard !isCollapsed else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await MainActor.run { self.catchUp() }
            }
        }
    }

    public func stopLiveUpdates() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Player actions

    /// Registers a photographed flower. The identification may still be
    /// running; pass what is known and call `attachIdentification` later.
    @discardableResult
    public func recordPhotograph(
        localIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        coordinate: GeoPoint?,
        takenAt: Date
    ) -> EntityID {
        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: localIdentifier,
            species: species,
            confidence: confidence,
            coordinate: coordinate,
            takenAt: takenAt
        )
        refresh()
        return patch.id
    }

    public func attachIdentification(
        _ species: FlowerSpecies,
        confidence: Double,
        to patch: EntityID
    ) {
        simulation.identifyPatch(patch, as: species, confidence: confidence)
        refresh()
    }

    public func setPatchLocation(_ patch: EntityID, coordinate: GeoPoint?) {
        simulation.setPatchLocation(patch, coordinate: coordinate)
        refresh()
    }

    public func assign(_ job: WorkerJob?, to bee: EntityID) {
        simulation.assign(job, to: bee)
        refresh()
    }

    /// Leans the colony toward one job. Returns how many bees were able to
    /// take it up, which is what the interface reports back to the player.
    @discardableResult
    public func emphasise(_ job: WorkerJob) -> Int {
        let assigned = simulation.emphasise(job)
        refresh()
        return assigned
    }

    public func clearAllAssignments() {
        simulation.clearAllAssignments()
        refresh()
    }

    public func relocateHive(to location: HiveLocation) {
        simulation.relocate(to: location)
        refresh()
    }

    /// The difficulty currently in force, so a settings screen can show which
    /// preset is selected.
    public var currentConfig: SimulationConfig { simulation.config }

    public func setDifficulty(_ config: SimulationConfig) {
        simulation.config = config
        refresh()
    }

    // MARK: - Watch

    /// The compact payload sent to the watch.
    public func watchSummary() -> WatchSummary {
        simulation.watchSummary(now: clock())
    }

    /// The whole colony, for sending to the watch.
    ///
    /// Views must never touch this — they get `snapshot`, which is the point
    /// of this type. It is here because the watch needs the *save*, not a
    /// summary: an App Group is not shared between devices, so the only way
    /// the watch gets a colony it can catch up itself is if the phone sends
    /// one. See `WatchLink`.
    public var simulationForTransfer: Simulation { simulation }

    // MARK: - Persistence

    private func refresh() {
        snapshot = simulation.snapshot()
        save()
    }

    private func save() {
        do {
            try persistence.save(simulation)
            lastError = nil
        } catch {
            // A failed save is worth surfacing but must never interrupt play.
            lastError = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Wipes the saved game and starts again. Destructive, so the caller is
    /// expected to have confirmed with the player first.
    ///
    /// - Parameter keepingFlowers: carries the garden across to the new
    ///   colony, which is the default and almost always what is wanted. The
    ///   photographs are the player's own record of places they went; the
    ///   flowers are still there whether or not the bees are. Passing `false`
    ///   is a genuine restart from nothing, for a player who asks for one.
    public func startNewGame(at site: HiveLocation, keepingFlowers: Bool = true) {
        simulation = Simulation.newGame(
            at: site,
            startingAt: clock(),
            config: simulation.config,
            seed: UInt64.random(in: 1...UInt64.max),
            inheriting: keepingFlowers ? simulation.patches : []
        )
        pendingReport = nil
        startLiveUpdates()
        refresh()
    }
}

// MARK: - Previews and tests

extension GameStore {

    /// A store backed by nothing on disk, for previews and tests.
    public static func preview(
        patches: Int = 10,
        daysToRun: Int = 60
    ) -> GameStore {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var simulation = Simulation.newGame(
            at: HiveLocation(
                coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                type: .livingTreeCavity
            ),
            startingAt: start,
            seed: 42
        )

        let species: [FlowerSpecies] = [
            FlowerSpecies(id: "clover", commonName: "White Clover",
                          scientificName: "Trifolium repens",
                          nectarRichness: 1.2, bloomSeasons: [.spring, .summer, .autumn]),
            FlowerSpecies(id: "borage", commonName: "Borage",
                          scientificName: "Borago officinalis", rarity: .uncommon,
                          nectarRichness: 1.8, bloomSeasons: [.summer]),
            FlowerSpecies(id: "heather", commonName: "Heather",
                          scientificName: "Calluna vulgaris", rarity: .uncommon,
                          nectarRichness: 1.6, bloomSeasons: [.autumn], isKeystone: true)
        ]

        for index in 0..<patches {
            simulation.registerPhotograph(
                photoLocalIdentifier: "preview-\(index)",
                species: index % 4 == 3 ? nil : species[index % species.count],
                confidence: 0.6 + Double(index % 4) * 0.1,
                coordinate: GeoPoint(
                    latitude: 51.5072 + Double(index % 5) * 0.002,
                    longitude: -0.1276 + Double(index % 3) * 0.003
                ),
                takenAt: start
            )
        }

        for _ in 0..<daysToRun { _ = simulation.stepDay() }

        return GameStore(
            simulation: simulation,
            persistence: InMemoryPersistence(),
            clock: { start.addingTimeInterval(Double(daysToRun) * 2 * 3600) }
        )
    }
}
