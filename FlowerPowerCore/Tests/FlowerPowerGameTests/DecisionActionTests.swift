import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

/// Answering a decision from somewhere that is not the app.
///
/// Two things are being tested, and they are different. The identifiers are a
/// *wire format*: they are registered with the notification centre, they sit on
/// a lock screen across an app update, and a watch can queue one for hours
/// before the phone hears it. They are asserted against their literal
/// spellings, because the point of the test is to notice if somebody tidies one
/// of them.
///
/// The rest is staleness. Every one of these answers can arrive after the
/// question has stopped being asked, and the rule is that a stale answer does
/// nothing at all rather than something almost right.
@Suite("Decision actions")
@MainActor
struct DecisionActionTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func makeStore(
        _ arrange: (inout Simulation) -> Void = { _ in }
    ) -> GameStore {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 21
        )
        arrange(&simulation)
        return GameStore(
            simulation: simulation,
            persistence: InMemoryPersistence(),
            clock: { self.epoch }
        )
    }

    /// A wasp at the door, with two days left to answer.
    private func besieged() -> GameStore {
        makeStore { simulation in
            simulation.world.activeThreat = ActiveThreat(
                predator: .wasp, beganOnDay: 0, resolvesOnDay: 2
            )
        }
    }

    /// Adults spread across the age range, so a colony is big enough to divide.
    private func crowd(_ world: inout World, adults: Int = 200) {
        world.hive.bees.append(contentsOf: (0..<adults).map { index in
            Bee(
                id: EntityID(rawValue: UInt64(70_000 + index)),
                kind: .worker, stage: .adult,
                daysInStage: index % 30
            )
        })
    }

    /// A swarm gathering, in a colony that could be divided onto a cell.
    private func dividable() -> GameStore {
        makeStore { simulation in
            crowd(&simulation.world)
            var cell = QueenCell(id: EntityID(rawValue: 80_001), purpose: .swarm)
            for _ in 0..<SimulationConfig.standard.splitEarliestCellDay {
                cell.advanceOneDay()
            }
            simulation.world.hive.comb.addQueenCell(cell)
            simulation.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
    }

    private func advance(_ simulation: inout Simulation, toDay day: Int) {
        while simulation.clock.day < day { simulation.clock.commitTick() }
    }

    // MARK: - Identifiers

    @Test("Every answer survives the round trip through its identifier")
    func identifiersRoundTrip() {
        for action in DecisionAction.all {
            let parsed = DecisionAction(identifier: action.identifier)
            #expect(parsed == action, "\(action.identifier) did not come back as itself")
        }
    }

    /// The literal spellings. These are what `NotificationActions` registered
    /// its buttons with before the vocabulary moved into the package, and a
    /// notification delivered by the old version comes back with the old
    /// string. Changing one of these is a breaking change, not a tidy-up.
    @Test("The identifiers are the ones already on people's lock screens", arguments: [
        (DecisionAction.posture(.holdEntrance), "posture.holdEntrance"),
        (.posture(.narrowEntrance), "posture.narrowEntrance"),
        (.posture(.foragersHome), "posture.foragersHome"),
        (.posture(.cleanersOut), "posture.cleanersOut"),
        (.posture(.instinct), "posture.instinct"),
        (.discourageSwarm, "swarm.discourage"),
        (.addComb, "nest.addComb"),
        (.split, "swarm.split"),
        (.letSwarmGo, "swarm.let"),
        (.staySwarm, "swarm.stay"),
        (.sealEntrance, "entrance.seal"),
        (.openEntrance, "entrance.open")
    ])
    func identifierSpellings(action: DecisionAction, identifier: String) {
        #expect(action.identifier == identifier)
        #expect(DecisionAction(identifier: identifier) == action)
    }

    @Test("Anything else parses as nothing at all", arguments: [
        // Following a swarm needs a site chosen, so it is deliberately not an
        // answer this can apply — it opens the app instead.
        "swarm.follow",
        "posture.",
        "posture.wanderOff",
        "nest.addcomb",
        "",
        "com.apple.UNNotificationDefaultActionIdentifier"
    ])
    func unknownIdentifiers(identifier: String) {
        #expect(DecisionAction(identifier: identifier) == nil)
    }

    @Test("The button labels are the posture's own words")
    func titles() {
        #expect(DecisionAction.posture(.holdEntrance).title == "Hold the Entrance")
        #expect(DecisionAction.discourageSwarm.title == "Make Room")
        #expect(DecisionAction.addComb.title == "Open the Nest Up")
        #expect(DecisionAction.split.title == "Divide Them")
        #expect(DecisionAction.letSwarmGo.title == "Let Them Go")
        #expect(DecisionAction.staySwarm.title == "Stay")
        #expect(DecisionAction.sealEntrance.title == "Seal It")
        #expect(DecisionAction.openEntrance.title == "Keep It Open")
    }

    // MARK: - A siege

    @Test("Answering an open siege adopts the posture")
    func postureOnOpenSiege() {
        let store = besieged()
        #expect(store.apply(.posture(.holdEntrance)))
        #expect(store.snapshot.posture == .holdEntrance)
        // The posture holds until the siege resolves, not for a flat few days.
        #expect(store.snapshot.postureDaysRemaining == 3)
    }

    @Test("Answering a siege that is over does nothing whatsoever")
    func postureOnStaleSiege() {
        let store = makeStore()
        let before = store.simulationForTransfer

        #expect(store.apply(.posture(.holdEntrance)) == false)
        #expect(store.snapshot.posture == .instinct)
        #expect(
            store.simulationForTransfer == before,
            "a stale answer must leave the colony byte-identical, not nearly so"
        )
    }

    // MARK: - A swarm

    @Test("Making room discourages the swarm and holds the posture")
    func discourageSwarm() {
        let store = makeStore { simulation in
            simulation.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        }
        #expect(store.apply(.discourageSwarm))
        #expect(store.snapshot.pendingSwarm?.discouraged == true)
        #expect(store.snapshot.posture == .makeRoom)
    }

    @Test("Making room after the swarm has gone does nothing")
    func discourageStaleSwarm() {
        let store = makeStore()
        let before = store.simulationForTransfer
        #expect(store.apply(.discourageSwarm) == false)
        #expect(store.simulationForTransfer == before)
    }

    @Test("Opening the nest up draws comb and spends the honey for it")
    func addComb() {
        let store = makeStore { simulation in
            simulation.world.hive.resources.add(500, of: .honey)
        }
        let cellsBefore = store.snapshot.nest.builtCells
        let honeyBefore = store.snapshot.stores.resources[.honey] ?? 0

        #expect(store.apply(.addComb))
        #expect(store.snapshot.nest.builtCells > cellsBefore)
        #expect((store.snapshot.stores.resources[.honey] ?? 0) < honeyBefore)
    }

    @Test("Opening a nest up that cannot afford the wax does nothing")
    func addCombWithoutHoney() {
        // Cavity to draw into, and an empty larder to draw it from. Wax costs
        // about seven times its own weight in stores, and the colony may not
        // spend below what it needs to keep laying — so this is the case where
        // a button would look live and do nothing.
        let store = makeStore { simulation in
            simulation.world.hive.resources.drain(1_000, of: .honey)
        }
        let before = store.simulationForTransfer
        #expect(store.apply(.addComb) == false)
        #expect(store.simulationForTransfer == before)
    }

    @Test("Dividing a colony that is ready sends half of it away")
    func split() {
        let store = dividable()
        #expect(store.apply(.split))
        #expect(store.snapshot.departedSwarm != nil)
    }

    @Test("Dividing after the swarm has already left is refused")
    func splitAfterTheSwarm() {
        // Everything in place except the pending swarm. This is the check that
        // stops a stale tap sending away a second half of a colony that has
        // just lost the first.
        let store = makeStore { simulation in
            crowd(&simulation.world)
            var cell = QueenCell(id: EntityID(rawValue: 80_002), purpose: .swarm)
            for _ in 0..<SimulationConfig.standard.splitEarliestCellDay {
                cell.advanceOneDay()
            }
            simulation.world.hive.comb.addQueenCell(cell)
        }
        let before = store.simulationForTransfer
        #expect(store.apply(.split) == false)
        #expect(store.simulationForTransfer == before)
    }

    @Test("Letting them go is answered by doing nothing at all")
    func letSwarmGo() {
        let store = makeStore { simulation in
            simulation.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        }
        let before = store.simulationForTransfer

        #expect(store.apply(.letSwarmGo), "the decision was answered, even though nothing was done")
        #expect(
            store.simulationForTransfer == before,
            "letting a swarm go is the absence of an action, not an action"
        )
    }

    @Test("Staying with the colony forgets the swarm that left")
    func staySwarm() {
        let store = dividable()
        #expect(store.apply(.split))
        #expect(store.snapshot.departedSwarm != nil)

        #expect(store.apply(.staySwarm))
        #expect(store.snapshot.departedSwarm == nil)

        // And again, with nothing left to decide.
        #expect(store.apply(.staySwarm) == false)
    }

    // MARK: - The entrance

    @Test("The entrance is decided in autumn", arguments: [true, false])
    func entranceInAutumn(sealed: Bool) {
        let store = makeStore { simulation in
            advance(&simulation, toDay: Season.daysPerSeason * 2 + 10)
            simulation.world.hive.resources.add(100, of: .propolis)
        }
        #expect(store.snapshot.season == .autumn)

        #expect(store.apply(sealed ? .sealEntrance : .openEntrance))
        #expect(store.simulationForTransfer.world.entranceDecision == sealed)
        #expect(store.snapshot.entranceSealed == sealed)
    }

    @Test("The entrance cannot be decided out of season")
    func entranceOutOfSeason() {
        let store = makeStore()
        #expect(store.snapshot.season == .spring)
        let before = store.simulationForTransfer

        #expect(store.apply(.sealEntrance) == false)
        #expect(
            store.simulationForTransfer == before,
            "a tap in December must not put a line in the almanac for something that did not happen"
        )
    }

    // MARK: - The seam with the watch

    /// The watch carries option identifiers as plain strings, because
    /// `WatchSummary` is in the engine and `DecisionAction` is a layer up. This
    /// is the test that keeps the two spellings the same: every option the
    /// engine offers has to parse back into an answer this can apply.
    @Test("Every option the watch offers parses back into an answer")
    func watchOptionsParse() {
        let sieges = [
            Predator.wasp,     // entrance
            .ant,              // pilfer
            .beeEater,         // field
            .waxMoth           // comb
        ].map { predator -> WatchDecision in
            var simulation = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 21
            )
            simulation.world.activeThreat = ActiveThreat(
                predator: predator, beganOnDay: 0, resolvesOnDay: 2
            )
            return simulation.watchSummary().decision!
        }

        for decision in sieges {
            #expect(!decision.options.isEmpty)
            for option in decision.options {
                let action = DecisionAction(identifier: option.identifier)
                #expect(action != nil, "the watch offers \(option.identifier), which nothing can apply")
                #expect(action?.title == option.title, "the same answer under two names")
            }
        }

        // And the same for every other kind of decision the watch can show.
        var swarming = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 21
        )
        swarming.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        var autumn = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 21
        )
        advance(&autumn, toDay: Season.daysPerSeason * 2 + 10)

        for simulation in [swarming, autumn] {
            let decision = simulation.watchSummary().decision
            #expect(decision != nil)
            for option in decision?.options ?? [] {
                #expect(
                    DecisionAction(identifier: option.identifier) != nil,
                    "the watch offers \(option.identifier), which nothing can apply"
                )
            }
        }
    }

    /// The watch applies an answer to its own copy for immediate feedback, and
    /// then sends it to the phone. Both ends run this same code, so a tap that
    /// the phone will refuse is a tap the watch refuses too — the two never
    /// disagree about whether a decision was stale.
    @Test("An answer applies the same way on either device")
    func bothEndsAgree() {
        let onPhone = besieged()
        let onWatch = besieged()

        #expect(onPhone.apply(.posture(.narrowEntrance)))
        #expect(onWatch.apply(.posture(.narrowEntrance)))
        #expect(onPhone.simulationForTransfer == onWatch.simulationForTransfer)
    }
}
