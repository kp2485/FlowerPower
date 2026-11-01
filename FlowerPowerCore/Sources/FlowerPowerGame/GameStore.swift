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

    /// True through a catch-up long enough to notice. Anything answered in
    /// that time would be answered on the colony as it was, so the interface
    /// holds still until it lands. `isBusy` is not it: that is also true for a
    /// moment every twenty seconds under the live ticker.
    public private(set) var isCatchingUp = false

    /// Counts the times this store's colony became a different colony: a new
    /// one, a swarm followed, a backup restored. For whatever the interface
    /// holds about the colony it was showing.
    public private(set) var colonyChanges = 0

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

    private var simulation: Simulation {
        // Every change, however it is made. A catch-up run off the main actor
        // compares this before and after, and throws its result away if the
        // colony changed underneath it.
        didSet { revision &+= 1 }
    }
    @ObservationIgnored private var revision = 0
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

    /// Set when `load` found a save it could not read and started the
    /// introduction instead. See `retryUnreadableSave()`.
    @ObservationIgnored private var hasUnreadableSaveAtLaunch = false

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
        // Not `try?`. That made a save which exists but will not decode look
        // exactly like no save at all: the player was sent back through the
        // introduction, and choosing a site there wrote a fresh colony over
        // the one that would not read — garden and all.
        var unreadable: String?
        do {
            if let saved = try persistence.load() {
                let store = GameStore(simulation: saved, persistence: persistence, clock: clock)
                // This colony came out of the save, so the save is this
                // store's until somebody else writes it.
                store.storedSaveToken = try? persistence.changeToken()
                return store
            }
        } catch {
            let kept = try? persistence.preserveUnreadable()
            unreadable = "Your saved colony could not be read (\(error.localizedDescription))."
                + (kept == nil ? "" : " A copy has been kept.")
                + " FlowerPower will try it again when you come back."
        }

        let fresh = Simulation.newGame(
            at: defaultSite,
            startingAt: clock(),
            seed: UInt64.random(in: 1...UInt64.max)
        )
        let store = GameStore(simulation: fresh, persistence: persistence, clock: clock)
        store.needsSetup = true
        store.lastError = unreadable
        store.hasUnreadableSaveAtLaunch = unreadable != nil
        return store
    }

    /// Looks again at a save that would not read at launch.
    ///
    /// One unreadable moment is not proof of a bad file. A launch before the
    /// phone's first unlock cannot read a protected file at all, and that used
    /// to leave the store on the introduction for the rest of the process,
    /// where choosing a site wrote a new colony over a perfectly good one.
    /// Called each time the app comes forward until the player settles it by
    /// choosing a site.
    public func retryUnreadableSave() {
        guard hasUnreadableSaveAtLaunch, needsSetup,
              let saved = try? persistence.load() else { return }
        hasUnreadableSaveAtLaunch = false
        needsSetup = false
        lastError = nil
        simulation = saved
        snapshot = simulation.snapshot()
        storedSaveToken = try? persistence.changeToken()
        colonyChanges += 1
    }

    // MARK: - Advancing time

    /// Brings the colony up to date. Safe to call on launch, on foreground, and
    /// as often as you like — the engine works out how much time has passed.
    ///
    /// - Parameter reporting: whether time that passes here is time the
    ///   player was away. The live ticker passes false: it advances a colony
    ///   the player is looking at, and when one of its ticks crossed midnight
    ///   it raised a full-screen "While you were away" about the last hour,
    ///   every simulated day, over whatever the player was doing.
    public func catchUp(reporting: Bool = true) {
        // Before anything else, because everything below reads the colony and
        // the last thing this does is write it over the save.
        takeInOutsideChanges()

        var advanced = simulation
        let report = advanced.advance(to: clock())
        let moved = advanced.clock != simulation.clock
        adopt(advanced, report: report, snapshot: moved ? advanced.snapshot() : nil, reporting: reporting)
    }

    /// The same, with the simulating done off the main actor.
    ///
    /// For the two callers that can be slow: coming back to the app, which
    /// may mean months of ticks after a long absence, and the live ticker,
    /// which runs every twenty seconds under whatever the player is doing.
    /// Both used to advance the colony and rebuild the snapshot on the main
    /// thread, where weeks away meant a frozen screen at launch.
    public func catchUpInBackground(reporting: Bool = true) async {
        guard !isBusy else { return }
        takeInOutsideChanges()

        let start = revision
        let now = clock()
        isBusy = true
        isCatchingUp = simulation.clock.pendingTicks(at: now) >= SimClock.ticksPerDay * 7
        let (advanced, report, fresh) = await Self.advanced(simulation, to: now)
        isBusy = false
        isCatchingUp = false

        // A button pressed, or a save taken in, while this was away: the
        // result is for a colony that no longer exists. Do it again here,
        // from the one that does.
        guard revision == start else {
            catchUp(reporting: reporting)
            return
        }
        adopt(advanced, report: report, snapshot: fresh, reporting: reporting)
    }

    @concurrent
    nonisolated private static func advanced(
        _ simulation: Simulation,
        to date: Date
    ) async -> (Simulation, CatchUpReport, ColonySnapshot?) {
        var advanced = simulation
        let report = advanced.advance(to: date)
        let moved = advanced.clock != simulation.clock
        return (advanced, report, moved ? advanced.snapshot() : nil)
    }

    /// Takes on a caught-up colony. `fresh` is nil when nothing moved — no
    /// tick fell due and the clock did not need rebasing — and then there is
    /// no snapshot to rebuild and nothing new to write. The ticker runs every
    /// twenty seconds and a tick lasts five minutes, so that is most of them;
    /// each one used to encode and write the whole colony regardless.
    private func adopt(
        _ advanced: Simulation,
        report: CatchUpReport,
        snapshot fresh: ColonySnapshot?,
        reporting: Bool
    ) {
        guard let fresh else { return }

        // Whether the colony was already gone before this catch-up. A player
        // returning to a colony that died last week should not be handed a
        // fresh report about the week of nothing that followed; they should be
        // shown the death once, and then the way to start again.
        let wasCollapsed = isCollapsed

        simulation = advanced
        snapshot = fresh

        if reporting, !wasCollapsed, !report.isEmpty {
            if let unread = pendingReport {
                // Still on screen, or backgrounded before it was read. Adding
                // to it rather than replacing it, which threw away everything
                // the first absence had to say.
                pendingReport = unread.merging(report)
            } else if report.daysSimulated >= 1 {
                pendingReport = report
            }
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
                await self.catchUpInBackground(reporting: false)
            }
        }
    }

    public func stopLiveUpdates() {
        ticker?.cancel()
        ticker = nil
    }

    /// For tests.
    var isRunningLiveUpdates: Bool { ticker != nil }

    // MARK: - Player actions

    /// Registers a photographed flower. The identification may still be
    /// running; pass what is known and call `attachIdentification` later.
    ///
    /// - Parameter cell: where the player asked for it, by tapping an empty
    ///   cell of the garden on the map. Honoured only if that cell is still
    ///   empty garden by the time the photograph lands; otherwise the engine
    ///   chooses, as it does for every other photograph.
    @discardableResult
    public func recordPhotograph(
        localIdentifier: String,
        species: FlowerSpecies?,
        confidence: Double,
        takenAt: Date,
        at cell: HexCoordinate? = nil
    ) -> EntityID {
        takeInOutsideChanges()
        let wanted = cell.flatMap { cell in
            snapshot.terrain?.garden.first { $0.cell == cell && $0.patchID == nil }?.cell
        }
        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: localIdentifier,
            species: species,
            confidence: confidence,
            takenAt: takenAt,
            at: wanted
        )
        refresh()
        return patch.id
    }

    public func attachIdentification(
        _ species: FlowerSpecies,
        confidence: Double,
        to patch: EntityID
    ) {
        takeInOutsideChanges()
        simulation.identifyPatch(patch, as: species, confidence: confidence)
        refresh()
    }

    public func assign(_ job: WorkerJob?, to bee: EntityID) {
        takeInOutsideChanges()
        simulation.assign(job, to: bee)
        refresh()
    }

    /// Leans the colony toward one job. Returns how many bees were able to
    /// take it up, which is what the interface reports back to the player.
    @discardableResult
    public func emphasise(_ job: WorkerJob) -> Int {
        takeInOutsideChanges()
        let assigned = simulation.emphasise(job)
        refresh()
        return assigned
    }

    /// See `Simulation.emphasisedJob`.
    public var emphasisedJob: WorkerJob? { simulation.emphasisedJob }

    public func clearAllAssignments() {
        takeInOutsideChanges()
        simulation.clearAllAssignments()
        refresh()
    }

    public func relocateHive(to location: HiveLocation) {
        takeInOutsideChanges()
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
        takeInOutsideChanges()
        simulation.config = config
        refresh()
    }

    // MARK: - Decisions

    /// Answers a siege with a posture. Ignored if the siege is over, and says
    /// so, because a card can outlive the siege it was drawn for by a tick.
    @discardableResult
    public func respond(to threat: ActiveThreat, with posture: HivePosture) -> Bool {
        takeInOutsideChanges()
        let answered = simulation.respond(to: threat, with: posture)
        refresh()
        return answered
    }

    public func adoptPosture(_ posture: HivePosture, forDays days: Int = 3) {
        takeInOutsideChanges()
        simulation.adoptPosture(posture, forDays: days)
        refresh()
    }

    /// Gives the colony more room, where the site allows it. Returns the cells
    /// added, so the interface can say what happened.
    @discardableResult
    public func addComb() -> Int {
        takeInOutsideChanges()
        let added = simulation.addComb()
        if added > 0 { refresh() }
        return added
    }

    /// Divides the colony on purpose. The half that leaves becomes the
    /// departed swarm, so the same three answers apply to it as to a real one:
    /// follow it, give it away, or let it go.
    @discardableResult
    public func splitColony() -> Bool {
        takeInOutsideChanges()
        let divided = simulation.split()
        if divided { refresh() }
        return divided
    }

    public func discourageSwarm() {
        takeInOutsideChanges()
        simulation.discourageSwarm()
        refresh()
    }

    public func acceptSwarm() {
        takeInOutsideChanges()
        simulation.acceptSwarm()
        refresh()
    }

    /// The autumn decision. Nil hands it back to instinct.
    public func decideEntrance(sealed: Bool?) {
        takeInOutsideChanges()
        simulation.decideEntrance(sealed: sealed)
        refresh()
    }

    @discardableResult
    public func takeHoney(_ units: Double) -> Double {
        takeInOutsideChanges()
        let taken = simulation.takeHoney(units)
        refresh()
        return taken
    }

    /// Gives banked honey back to a colony that is short. Returns what
    /// actually went in, which is capped by the bank and by the comb there is
    /// to store it in.
    @discardableResult
    public func feed(_ units: Double) -> Double {
        takeInOutsideChanges()
        let given = simulation.feed(units)
        if given > 0 { refresh() }
        return given
    }

    /// Sends a scouting party out for three days.
    ///
    /// - Returns: whether they went. False means the decision was not open —
    ///   the flow has ended, a party is already out, or there is no rumoured
    ///   ground left to find.
    @discardableResult
    public func sendScouts() -> Bool {
        takeInOutsideChanges()
        guard simulation.sendScouts() else { return false }
        refresh()
        return true
    }

    public func nameQueen(_ number: Int, _ name: String?) {
        takeInOutsideChanges()
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
        // A colony the player chose, so the introduction is over. See
        // `startNewGame`.
        needsSetup = false
        simulation = followed
        pendingReport = nil
        colonyChanges += 1
        // Refreshed first: `startLiveUpdates` asks the snapshot whether there
        // is a colony to run, and the snapshot here may still be a dead one.
        refresh()
        startLiveUpdates()
    }

    /// Stays with the parent colony. The swarm is gone.
    public func letSwarmGo() {
        takeInOutsideChanges()
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
        // Can arrive during the introduction — a file opened from Messages on
        // a first run — and the colony it founds is a choice, not a
        // placeholder. Without this it was never saved.
        needsSetup = false
        simulation = Simulation.newGame(
            fromSwarm: share.departedSwarm(),
            at: site,
            startingAt: clock(),
            config: simulation.config,
            seed: UInt64.random(in: 1...UInt64.max),
            inheriting: simulation.patches,
            inheritedOnDay: simulation.clock.day,
            importedShares: simulation.world.importedShares,
            generation: simulation.world.lineage.generation + 1,
            queenName: share.queen?.name
        )
        pendingReport = nil
        colonyChanges += 1
        // After the refresh, for the reason in `followSwarm`.
        refresh()
        startLiveUpdates()
    }

    // MARK: - Asking for a flower

    /// What the colony is short of right now, for a request to a friend:
    /// families flowering this season that the garden has nothing workable
    /// in.
    public func forageRequest(from senderName: String?, note: String? = nil) -> FlowerShare {
        let season = snapshot.season
        // Modelled families only: a request names what the catalogue can
        // describe, and a friend can only send what they can name.
        let workable = Set(snapshot.patches.filter(\.isInBloom).compactMap { $0.family?.known })
        let wanted = Set(FlowerCatalogue.inBloom(during: season).compactMap(\.family.known))
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
    public func share(
        patch id: EntityID,
        imageData: Data,
        from senderName: String?,
        note: String? = nil
    ) -> FlowerShare? {
        guard let patch = simulation.patches.first(where: { $0.id == id }) else { return nil }

        // Validated on the way out as well as on the way in, so an empty name
        // typed and then deleted travels as no name rather than as "".
        let species = patch.species
        return FlowerShare(
            speciesID: species?.id,
            taxon: species?.taxon,
            taxonCommonName: species?.commonName,
            confidence: patch.identificationConfidence,
            takenAt: patch.discoveredAt,
            sharedBy: senderName,
            note: note,
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
        takeInOutsideChanges()
        let share = share.validated()

        guard let patch = simulation.importSharedFlower(
            shareID: share.id,
            photoLocalIdentifier: share.localIdentifier,
            species: share.species,
            confidence: share.confidence,
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
        // The new-phone case: a backup opened before any site was chosen.
        // Still gated, the restored colony was never saved, and choosing a
        // site afterwards replaced it.
        needsSetup = false
        var restored = archive.simulation
        // Picks up from the moment it was saved. Left on its own clock, the
        // colony ran every hour since the backup in one silent catch-up twenty
        // seconds later: the screen promised day 120 and delivered day 240 and
        // often a dead one, so restoring to undo a death just repeated it.
        restored.resumeClock(at: clock())
        simulation = restored
        pendingReport = nil
        colonyChanges += 1
        // Refreshed before the ticker. A restored colony may be a dead one —
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
    ///
    /// Also run at the start of every player action, which mutates and then
    /// saves without catching up. Without it a button pressed in the seconds
    /// between a widget, notification or background refresh writing the file
    /// and the next tick wrote this store's older colony over that one.
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
        // The last chance to keep a save that would not read, which this is
        // about to write over. The copy made at launch can itself have failed.
        if hasUnreadableSaveAtLaunch {
            _ = try? persistence.preserveUnreadable()
            hasUnreadableSaveAtLaunch = false
        }
        // A site has been chosen, so there is a colony worth keeping. Cleared
        // before the calls below, both of which are gated on it.
        needsSetup = false
        simulation = Simulation.newGame(
            at: site,
            startingAt: clock(),
            config: simulation.config,
            seed: UInt64.random(in: 1...UInt64.max),
            inheriting: keepingFlowers ? simulation.patches : [],
            inheritedOnDay: simulation.clock.day,
            importedShares: keepingFlowers ? simulation.world.importedShares : []
        )
        pendingReport = nil
        colonyChanges += 1
        // After the refresh, for the reason in `followSwarm`. This is what
        // "Begin Again" calls, and the other order left the new colony's
        // dashboard frozen until the app next came to the foreground.
        refresh()
        startLiveUpdates()
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
            at: HiveLocation(type: .livingTreeCavity),
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
