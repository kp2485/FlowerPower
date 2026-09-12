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

    /// Whether this is a colony nobody has chosen yet.
    ///
    /// `load` always hands back a playable store — there has to be something
    /// to render — so when there is no save it starts a colony at a default
    /// site. That default is a placeholder, not a choice: where the swarm
    /// settles decides more about the next two years than anything the player
    /// picks afterwards, so a first-run player must get to choose it.
    ///
    /// While this is true the store keeps the placeholder colony out of the
    /// save file. A player who quits half way through the introduction should
    /// come back to the introduction, not to a colony living in a tree they
    /// never saw. It is cleared by `startNewGame`, which is what the
    /// site-choosing screen calls.
    public private(set) var needsSetup = false

    // MARK: - Private state

    private var simulation: Simulation
    private let persistence: GamePersisting
    private let clock: () -> Date

    /// What the persistence said about the stored colony the last time this
    /// store wrote it or read it. See `takeInOutsideChanges()`.
    ///
    /// Nil means this store has never had anything to do with the save —
    /// a first run before a site is chosen, or one of the throwaway stores
    /// built around a simulation already in hand — and there is then nothing
    /// to compare a token against and no file this store has any claim on.
    private var storedSaveToken: String?

    /// Set while the store cannot tell whether the save is still its own, or
    /// cannot read the one that replaced it.
    ///
    /// Survives a successful write rather than being cleared by it, because
    /// the write is the worrying half: it is the moment the store puts its own
    /// colony over a file it could not read, and whatever somebody else had
    /// decided in there goes with it.
    private var unreadableSave: String?

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
    ///
    /// A store that had nothing to load comes back with `needsSetup` set, so
    /// the interface can tell a first run from a returning player — which
    /// used to be indistinguishable, and meant a new player landed on a
    /// dashboard full of numbers with no idea what any of it was.
    public static func load(
        persistence: GamePersisting = GamePersistence(),
        defaultSite: HiveLocation = HiveLocation(type: .livingTreeCavity),
        clock: @escaping () -> Date = Date.init
    ) -> GameStore {
        if let saved = try? persistence.load() {
            let store = GameStore(simulation: saved, persistence: persistence, clock: clock)
            // This colony came out of the save, so the save is this store's
            // until somebody else writes it.
            store.storedSaveToken = try? persistence.changeToken()
            return store
        }

        let fresh = Simulation.newGame(
            at: defaultSite,
            startingAt: clock(),
            seed: UInt64.random(in: 1...UInt64.max)
        )
        let store = GameStore(simulation: fresh, persistence: persistence, clock: clock)
        store.needsSetup = true
        return store
    }

    // MARK: - Advancing time

    /// Brings the colony up to date. Safe to call on launch, on foreground, and
    /// as often as you like — the engine works out how much time has passed.
    public func catchUp() {
        // Before anything else, because everything below reads the colony and
        // the last thing this does is write it over the save.
        takeInOutsideChanges()

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
        // the phone awake to recompute the same empty nest for ever. Nor
        // before setup: a ticker would run the placeholder colony forward
        // underneath the introduction, and its catch-ups would be the first
        // thing to hand the player a report about a nest they have not seen.
        guard !isCollapsed, !needsSetup else { return }
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

    /// What this colony has done for the first time.
    ///
    /// Read straight from the simulation rather than copied into the snapshot:
    /// the badge page is a whole screen of its own that nothing on the
    /// dashboard reads, and two dozen records in every published snapshot
    /// would be paid for on every refresh.
    public var milestones: Milestones { simulation.milestones }

    /// The difficulty currently in force, so a settings screen can show which
    /// preset is selected.
    public var currentConfig: SimulationConfig { simulation.config }

    /// The colony's day-by-day record, for the charts.
    ///
    /// Computed over the stored simulation rather than copied into a published
    /// property: `@Observable` tracks the read either way, and two years of
    /// samples should not be duplicated on every refresh when only the newest
    /// one has changed.
    public var history: ColonyHistory { simulation.history }

    public func setDifficulty(_ config: SimulationConfig) {
        simulation.config = config
        refresh()
    }

    // MARK: - Decisions

    /// Answers a siege with a posture. Ignored if the siege is over.
    public func respond(to threat: ActiveThreat, with posture: HivePosture) {
        simulation.respond(to: threat, with: posture)
        refresh()
    }

    public func adoptPosture(_ posture: HivePosture, forDays days: Int = 3) {
        simulation.adoptPosture(posture, forDays: days)
        refresh()
    }

    /// Gives the colony more room, where the site allows it. Returns the cells
    /// added, so the interface can say what happened.
    @discardableResult
    public func addComb() -> Int {
        let added = simulation.addComb()
        if added > 0 { refresh() }
        return added
    }

    /// Divides the colony on purpose. The half that leaves becomes the
    /// departed swarm, so the same three answers apply to it as to a real one:
    /// follow it, give it away, or let it go.
    @discardableResult
    public func splitColony() -> Bool {
        let divided = simulation.split()
        if divided { refresh() }
        return divided
    }

    public func discourageSwarm() {
        simulation.discourageSwarm()
        refresh()
    }

    /// The autumn decision. Nil hands it back to instinct.
    public func decideEntrance(sealed: Bool?) {
        simulation.decideEntrance(sealed: sealed)
        refresh()
    }

    @discardableResult
    public func takeHoney(_ units: Double) -> Double {
        let taken = simulation.takeHoney(units)
        refresh()
        return taken
    }

    public func nameQueen(_ number: Int, _ name: String?) {
        simulation.nameQueen(number, name)
        refresh()
    }

    /// Goes with the swarm that just left: a new colony from the old queen
    /// and the bees who followed her, at a site of the player's choosing. The
    /// garden comes too. The parent colony is left to its virgin queen.
    public func followSwarm(to site: HiveLocation) {
        guard let followed = simulation.followingSwarm(
            to: site, startingAt: clock(), seed: UInt64.random(in: 1...UInt64.max)
        ) else { return }
        simulation = followed
        pendingReport = nil
        startLiveUpdates()
        refresh()
    }

    /// Stays with the parent colony. The swarm is gone.
    public func letSwarmGo() {
        simulation.forgetLastSwarm()
        refresh()
    }

    /// Winter clock speed. See `SimClock.winterSpeed`.
    public var winterSpeed: Double {
        get { simulation.winterSpeed }
        set {
            simulation.winterSpeed = newValue
            refresh()
        }
    }

    // MARK: - Sharing swarms

    /// Packages the swarm that just left, to give to somebody.
    public func shareSwarm(from senderName: String?, note: String? = nil) -> SwarmShare? {
        guard let swarm = simulation.world.lastSwarm else { return nil }
        return SwarmShare(
            swarm, lineage: simulation.world.lineage,
            sharedBy: senderName, note: note
        ).validated()
    }

    /// Founds a colony from a swarm somebody sent, at a site of the player's
    /// choosing. Replaces the current colony, so the interface confirms first
    /// unless the current one is already gone. The garden stays.
    public func adoptSwarm(_ share: SwarmShare, at site: HiveLocation) {
        let share = share.validated()
        simulation = Simulation.newGame(
            fromSwarm: share.departedSwarm(),
            at: site,
            startingAt: clock(),
            config: simulation.config,
            seed: UInt64.random(in: 1...UInt64.max),
            inheriting: simulation.patches,
            generation: simulation.world.lineage.generation + 1
        )
        pendingReport = nil
        startLiveUpdates()
        refresh()
    }

    // MARK: - Asking for a flower

    /// What the colony is short of right now, for a request to a friend:
    /// families flowering this season that the garden has nothing workable
    /// in.
    public func forageRequest(from senderName: String?, note: String? = nil) -> FlowerShare {
        let season = snapshot.season
        let workable = Set(snapshot.patches.filter(\.isInBloom).compactMap(\.family))
        let wanted = Set(FlowerCatalogue.inBloom(during: season).map(\.family))
            .subtracting(workable)
            .sorted { $0.scientificName < $1.scientificName }

        return FlowerShare.request(
            wanted: wanted, season: season,
            sharedBy: senderName, note: note
        ).validated()
    }

    // MARK: - Sharing flowers

    /// Packages one of the player's flowers to send to somebody.
    ///
    /// The image is supplied by the caller rather than fetched here, because
    /// the engine has no idea what a photograph is — it stores an identifier
    /// and nothing else. The app loads and downscales the picture and hands
    /// the bytes in.
    ///
    /// - Parameter location: how precisely to say where it was found.
    ///   Defaults to not saying at all. See `FlowerShare` for why that is the
    ///   default rather than a setting somebody has to find.
    public func share(
        patch id: EntityID,
        imageData: Data,
        from senderName: String?,
        note: String? = nil,
        location: LocationSharing = .none
    ) -> FlowerShare? {
        guard let patch = simulation.patches.first(where: { $0.id == id }) else { return nil }

        let coordinate = location.apply(to: patch.coordinate)

        // Validated on the way out as well as on the way in, so an empty name
        // typed and then deleted travels as no name rather than as "".
        return FlowerShare(
            speciesID: patch.species?.id,
            confidence: patch.identificationConfidence,
            takenAt: patch.discoveredAt,
            sharedBy: senderName,
            note: note,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            imageData: imageData
        ).validated()
    }

    public enum ImportOutcome: Equatable {
        case added(EntityID)
        /// Already taken in. Worth saying so: silently doing nothing looks
        /// like a bug, and a share stays tappable in a message thread for ever.
        case alreadyHave
    }

    /// Takes in a flower somebody sent.
    @discardableResult
    public func importShared(_ share: FlowerShare) -> ImportOutcome {
        let share = share.validated()

        guard let patch = simulation.importSharedFlower(
            shareID: share.id,
            photoLocalIdentifier: share.localIdentifier,
            species: share.species,
            confidence: share.confidence,
            coordinate: share.coordinate,
            takenAt: share.takenAt,
            sharedBy: share.sharedBy
        ) else {
            return .alreadyHave
        }

        refresh()
        return .added(patch.id)
    }

    public func hasImported(_ share: FlowerShare) -> Bool {
        simulation.hasImported(shareID: share.id)
    }

    // MARK: - Backing the colony up

    /// Packages the whole colony into a file the player can keep.
    ///
    /// Throws rather than returning nil because there is nothing to fall back
    /// on: if the colony will not encode, the save on disk is in the same
    /// trouble, and the player should be told rather than handed an empty
    /// file.
    public func exportArchive() throws -> Data {
        try SaveArchive(simulation: simulation).encode()
    }

    /// Replaces this device's colony with the one in a backup.
    ///
    /// Destructive and irreversible — the colony that was here is gone the
    /// moment this saves — so the caller is expected to have confirmed with
    /// the player first, exactly as `startNewGame` is. Unlike `startNewGame`
    /// there is no keeping the garden: the archive carries its own garden, and
    /// merging two would invent patches the player never photographed.
    ///
    /// Saved immediately rather than at the next tick, so a player who
    /// restores and then force-quits still has the colony they asked for.
    public func restore(from archive: SaveArchive) {
        simulation = archive.simulation
        pendingReport = nil
        // Refreshed before the ticker rather than after, which is the other
        // way round from `startNewGame`. A restored colony may be a dead one —
        // a player keeping a backup of a colony that later collapsed is an
        // obvious reason to have one — and `startLiveUpdates` decides whether
        // to run from the snapshot, so it has to be looking at the restored
        // colony and not the one being replaced.
        refresh()
        startLiveUpdates()
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

    /// Takes in a colony another process wrote while this store was holding
    /// one in memory.
    ///
    /// The save file has four writers. Three of them act on the file alone,
    /// because they have to: a tapped notification action, a widget button and
    /// a Shortcut can all arrive with no interface running at all, and each
    /// loads the save, applies the answer and writes it back. The fourth is
    /// this store, which keeps the colony in memory and writes over the file
    /// on every catch-up. So a decision answered from the lock screen while
    /// the app was in the foreground — or merely suspended with the store
    /// still alive — used to be overwritten by the store's next tick, twenty
    /// seconds later, with no sign that anything had been lost. That is the
    /// bug this closes, and it is closed here rather than in each of those
    /// three writers because they are all correct: the file *is* the only
    /// thing they can act on.
    ///
    /// Two deliberate silences.
    ///
    /// **No report.** The colony that arrives has already been advanced to the
    /// moment the other process saw, and the report it produced there was
    /// thrown away; `catchUp` goes on to advance from there to now and reports
    /// that much. The hours the other process simulated are not narrated
    /// twice, and not narrated at all. That is the same thing a cold launch
    /// has always done — a store that loads the save narrates only what it
    /// advances — so the exchange is a few hours of narration for a colony
    /// that is actually the one the player decided about.
    ///
    /// **No dismissal.** A `pendingReport` the player has not read yet stays
    /// put. Those events happened, the player has not been shown them, and
    /// clearing the sheet out from under them because a widget button was
    /// pressed would lose the one thing this store exists to say.
    private func takeInOutsideChanges() {
        // A store with no claim on the save must not reload one. That is a
        // first run, where the colony is a placeholder nobody has chosen and
        // the file may hold the colony the player is about to replace; and it
        // is the throwaway stores those three writers build, which have just
        // read the file themselves.
        guard !needsSetup, let known = storedSaveToken else { return }

        // Cleared here rather than anywhere else: this runs on every
        // catch-up, so a condition that is still true will set it again and
        // one that has gone away stops being reported.
        unreadableSave = nil

        let current: String?
        do {
            current = try persistence.changeToken()
        } catch {
            // Not being able to ask is not a reason to discard anything.
            unreadableSave = "Could not check the save: \(error.localizedDescription)"
            lastError = unreadableSave
            return
        }

        // Nothing stored at all means somebody cleared the file rather than
        // wrote it, and the colony in memory is now the only copy there is.
        // Keeping it is what saves it: the write at the end of `catchUp` puts
        // it back.
        guard let current, current != known else { return }

        do {
            guard let stored = try persistence.load() else { return }
            simulation = stored
            snapshot = simulation.snapshot()
            storedSaveToken = current
        } catch {
            // Keep what we have. A save this store cannot read is a worse
            // thing to hold than one it has in memory, and the player is told
            // because the next write will overwrite whatever is down there.
            unreadableSave = "Could not re-read the save: \(error.localizedDescription)"
            lastError = unreadableSave
        }
    }

    private func refresh() {
        snapshot = simulation.snapshot()
        save()
    }

    /// Writes the colony down, and remembers what the save looked like
    /// afterwards so `takeInOutsideChanges` can recognise its own work.
    ///
    /// Deliberately does *not* reload first, though it is a write over the
    /// same file. By the time this runs the change is already in the
    /// simulation — every caller mutates and then refreshes — so reloading
    /// here would throw away the action the player just took. The two cases
    /// are not the same shape: a timer overwriting a decision is a bug, and
    /// two of the player's own actions seconds apart in two processes is a
    /// race that the later one should win. The store's catch-up runs on
    /// foreground and every twenty seconds thereafter, which is how long that
    /// window can be.
    private func save() {
        // Not while the player is still being introduced. The colony this
        // would write is the placeholder one `load` invented, at a site
        // nobody chose. The gate is here rather than in `catchUp()` because
        // every player action ends in `refresh()`, which ends here — and a
        // watch tap or a widget button can arrive during the introduction.
        guard !needsSetup else { return }
        do {
            try persistence.save(simulation)
            storedSaveToken = try? persistence.changeToken()
            // Not `nil`: a write that succeeded does not undo the store's
            // having been unable to read what it wrote over.
            lastError = unreadableSave
        } catch {
            // A failed save is worth surfacing but must never interrupt play.
            lastError = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Wipes the saved game and starts again. Destructive, so the caller is
    /// expected to have confirmed with the player first — except on a first
    /// run, where there is nothing to destroy and this is simply how the
    /// introduction ends: the same site-choosing screen, and `needsSetup`
    /// cleared here so the colony starts being saved.
    ///
    /// - Parameter keepingFlowers: carries the garden across to the new
    ///   colony, which is the default and almost always what is wanted. The
    ///   photographs are the player's own record of places they went; the
    ///   flowers are still there whether or not the bees are. Passing `false`
    ///   is a genuine restart from nothing, for a player who asks for one.
    public func startNewGame(at site: HiveLocation, keepingFlowers: Bool = true) {
        // A site has been chosen, so there is a colony worth keeping. Cleared
        // before the calls below, both of which are gated on it.
        needsSetup = false
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

        // Real catalogue entries rather than hand-built ones, so a preview
        // shows the same taxonomy, corolla depths and pollen quality the game
        // actually runs on.
        let species = [
            FlowerCatalogue.whiteClover,
            FlowerCatalogue.borage,
            FlowerCatalogue.heather
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
