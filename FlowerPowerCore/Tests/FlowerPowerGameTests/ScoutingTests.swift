import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

/// The one decision the world adds, end to end, and the one sentence it adds
/// to the bloom prompt.
///
/// "Send scouts" is deliberately built in exactly the shape the five existing
/// decisions take — an identifier on the wire, a case in `GameStore.apply`, a
/// card on the watch, a line of news — so most of what is worth testing is
/// that it behaves like the others: it is refused when it is stale, and it
/// spells itself the same way every time.
@Suite("Scouting and directions")
@MainActor
struct ScoutingTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(flowing: Bool) -> GameStore {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 2026
        )
        if flowing {
            // A flow, stated directly. Reaching one by running a simulation is
            // luck rather than testing.
            simulation.world.recentNectarIntake = Array(
                repeating: Double(simulation.hive.adultCount) * 10, count: 7
            )
        }
        return GameStore(
            simulation: simulation,
            persistence: InMemoryPersistence(),
            clock: { self.epoch }
        )
    }

    // MARK: - The wire

    @Test("The identifier is the spelling it was registered with")
    func identifierIsStable() {
        #expect(DecisionAction.scout.identifier == "colony.scout")
        #expect(DecisionAction(identifier: "colony.scout") == .scout)
        #expect(DecisionAction.scout.title == "Send Scouts")
        #expect(DecisionAction.all.contains(.scout))
    }

    @Test("Every answer still round-trips")
    func everyActionRoundTrips() {
        for action in DecisionAction.all {
            #expect(DecisionAction(identifier: action.identifier) == action)
        }
    }

    // MARK: - Applying one

    @Test("A flow with rumoured ground sends them")
    func applySendsThem() {
        let store = makeStore(flowing: true)
        #expect(store.snapshot.scoutDecisionOpen)

        let sent = store.apply(.scout)
        #expect(sent)
        #expect(store.snapshot.scoutsOut)
        #expect(store.snapshot.scoutsDaysRemaining == SimulationConfig.standard.scoutDays)
        #expect(store.snapshot.terrain?.scoutsOut == true)
    }

    @Test("A stale answer does nothing at all")
    func staleAnswerIsRefused() {
        let store = makeStore(flowing: false)
        #expect(store.snapshot.scoutDecisionOpen == false)
        let sent = store.apply(.scout)
        #expect(sent == false)
        #expect(store.snapshot.scoutsOut == false)
    }

    @Test("Answering twice sends one party")
    func answeringTwiceSendsOneParty() {
        let store = makeStore(flowing: true)
        let first = store.apply(.scout)
        let second = store.apply(.scout)
        #expect(first)
        #expect(second == false)
        #expect(store.snapshot.scoutsOut)
    }

    // MARK: - The watch

    @Test("The watch offers it, with an identifier the phone can parse")
    func watchOffersIt() {
        let store = makeStore(flowing: true)
        let summary = store.watchSummary()

        guard let decision = summary.decision else {
            Issue.record("the watch was offered nothing")
            return
        }
        #expect(decision.kind == .scout)
        #expect(decision.title == "Ground they have not seen")
        for option in decision.options {
            #expect(DecisionAction(identifier: option.identifier) != nil)
        }
        #expect(decision.options.map(\.identifier) == ["colony.scout"])
    }

    @Test("And stops offering it once they have gone")
    func watchStopsOffering() {
        let store = makeStore(flowing: true)
        let sent = store.apply(.scout)
        #expect(sent)
        #expect(store.watchSummary().decision?.kind != .scout)
    }

    // MARK: - The news

    @Test("The window opening is worth saying once")
    func newsWhenTheWindowOpens() {
        let shut = ColonyNews.Facts(status: .steady, scoutDecisionOpen: false)
        let open = ColonyNews.Facts(
            status: .steady, day: 40, scoutDecisionOpen: true, rumouredChunks: 6
        )

        let news = ColonyNews.between(before: shut, after: open)
        #expect(news?.identifier == "scout-0")
        #expect(news?.body.contains("6 stretches") == true)

        // And not again while it stays open.
        #expect(ColonyNews.between(before: open, after: open) == nil)
    }

    @Test("Nothing to say when there is nothing to find")
    func noNewsWithoutRumours() {
        let shut = ColonyNews.Facts(status: .steady, scoutDecisionOpen: false)
        let open = ColonyNews.Facts(
            status: .steady, day: 40, scoutDecisionOpen: true, rumouredChunks: 0
        )
        #expect(ColonyNews.between(before: shut, after: open) == nil)
    }

    // MARK: - The direction in the bloom prompt

    /// A colony on the moor in August: the heather is out on ground the bees
    /// have found, and the prompt says which way it is.
    @Test("The bloom prompt points at a keystone out in the country")
    func bloomPromptGivesADirection() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 31
        )
        let onTheMoor = simulation.setTerrainBiome(.heath)
        #expect(onTheMoor)

        let snapshot = simulation.snapshot()
        // Late August in the northern hemisphere, when the moor is out.
        let august = Date(timeIntervalSince1970: 1_692_000_000)

        let prompt = BloomPrompt(
            date: august, patches: snapshot.patches, terrain: snapshot.terrain,
            wildPatches: snapshot.wildPatches
        )

        guard let sentence = prompt.wildKeystone else {
            Issue.record("no keystone found on a moor in August")
            return
        }
        #expect(sentence.hasSuffix("."))
        #expect(HexCoordinate.compassNames.contains { sentence.contains("to the \($0).") })

        // It names a stretch of country the colony actually knows.
        let names = snapshot.terrain?.discovered.map(\.name) ?? []
        #expect(names.contains { sentence.contains($0) })
    }

    @Test("No terrain, no direction")
    func bloomPromptStaysSilentWithoutTerrain() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 31
        )
        simulation.world.terrain = nil
        simulation.world.removeWildPatches()

        let snapshot = simulation.snapshot()
        let prompt = BloomPrompt(
            patches: snapshot.patches, terrain: snapshot.terrain,
            wildPatches: snapshot.wildPatches
        )
        #expect(prompt.wildKeystone == nil)
    }

    @Test("A garden flower is not a direction")
    func gardenFlowersAreNotDirections() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 31
        )
        _ = simulation.setTerrainBiome(.farmland)
        simulation.world.removeWildPatches()
        simulation.registerPhotograph(
            photoLocalIdentifier: "mine", species: FlowerCatalogue.heather,
            confidence: 0.9, takenAt: epoch
        )

        let snapshot = simulation.snapshot()
        let august = Date(timeIntervalSince1970: 1_692_000_000)
        let prompt = BloomPrompt(
            date: august, patches: snapshot.patches, terrain: snapshot.terrain,
            wildPatches: snapshot.wildPatches
        )
        #expect(prompt.wildKeystone == nil, "the garden is not somewhere to be pointed at")
    }
}
