import Testing
import Foundation
@testable import FlowerPowerCore

/// What the watch is asked to show.
///
/// The watch's whole justification is that a decision can be answered from the
/// wrist, so the summary has to carry the decision *and its answers*. These are
/// about which question gets asked: only one at a time, only while it is still
/// open, and never one whose answers do not fit on a watch.
@Suite("Watch decisions")
struct WatchDecisionTests {

    private func quiet() -> Simulation {
        Fixture.thrivingSimulation(config: .standard, seed: 21)
    }

    private func besieged(by predator: Predator = .wasp) -> Simulation {
        var simulation = quiet()
        simulation.mutateWorld { world in
            world.activeThreat = ActiveThreat(
                predator: predator, beganOnDay: 0, resolvesOnDay: 2
            )
        }
        return simulation
    }

    // MARK: - A siege

    @Test("A siege arrives with the postures that can answer it")
    func siegeCarriesItsOptions() throws {
        let summary = besieged().watchSummary()
        let decision = try #require(summary.decision)

        #expect(summary.hasDecision)
        #expect(decision.kind == .siege)
        #expect(decision.title == "Wasp at the nest")
        #expect(decision.daysRemaining == 2)
        #expect(decision.options.map(\.title) == ["Hold the Entrance", "Narrow the Entrance"])
        #expect(decision.options.map(\.identifier)
                == ["posture.holdEntrance", "posture.narrowEntrance"])
    }

    @Test("Instinct is not offered as a button")
    func instinctIsNotAButton() {
        // It is what happens if the player does nothing, and a button for
        // doing nothing would take a place on a watch that has about three.
        let decision = besieged().watchSummary().decision
        #expect(decision?.options.contains(where: { $0.identifier == "posture.instinct" }) == false)
    }

    @Test("A siege nothing can be done about is not a decision", arguments: [
        Predator.bear, .human
    ])
    func catastropheIsNotADecision(predator: Predator) {
        #expect(besieged(by: predator).watchSummary().decision == nil)
    }

    @Test("A siege already answered stops asking")
    func answeredSiegeIsClosed() throws {
        var simulation = besieged()
        let threat = try #require(simulation.world.activeThreat)
        simulation.respond(to: threat, with: .holdEntrance)

        #expect(
            simulation.watchSummary().decision == nil,
            "a decision the player has answered must not keep asking"
        )
    }

    // MARK: - A swarm

    @Test("A gathering swarm offers making room first")
    func swarmOptionsAreInMeasuredOrder() throws {
        var simulation = quiet()
        simulation.mutateWorld { world in
            world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        }
        let decision = try #require(simulation.watchSummary().decision)

        #expect(decision.kind == .swarm)
        #expect(decision.daysRemaining == 6)
        // Measured over 200 colonies across two years: 76% two-year survival
        // for making room, 66% for doing nothing, 62% for adding comb, 56% for
        // dividing. The best answer is the oldest one, so it goes first.
        #expect(decision.options.first?.identifier == "swarm.discourage")
        #expect(decision.options.last?.identifier == "swarm.let")
    }

    @Test("A swarm already discouraged stops asking")
    func discouragedSwarmIsClosed() {
        var simulation = quiet()
        simulation.mutateWorld { world in
            world.pendingSwarm = PendingSwarm(
                startedOnDay: 0, departsOnDay: 6, discouraged: true
            )
        }
        #expect(simulation.watchSummary().decision == nil)
    }

    @Test("Dividing is only offered where it is actually possible")
    func splitIsNotOfferedToASmallColony() throws {
        var simulation = quiet()
        simulation.mutateWorld { world in
            world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 6)
        }
        #expect(simulation.canSplit == false, "a founding colony has nothing to divide")
        let decision = try #require(simulation.watchSummary().decision)
        #expect(decision.options.contains(where: { $0.identifier == "swarm.split" }) == false)
    }

    // MARK: - The autumn entrance

    @Test("Autumn asks about the entrance")
    func autumnEntrance() throws {
        var simulation = quiet()
        simulation.setDay(Season.daysPerSeason * 2 + 10)
        let decision = try #require(simulation.watchSummary().decision)

        #expect(decision.kind == .entrance)
        #expect(decision.daysRemaining == nil, "this one is a state, not a countdown")
        #expect(decision.options.map(\.identifier) == ["entrance.seal", "entrance.open"])
    }

    @Test("The entrance stops being asked once it has been answered")
    func answeredEntranceIsClosed() {
        var simulation = quiet()
        simulation.setDay(Season.daysPerSeason * 2 + 10)
        simulation.decideEntrance(sealed: false)
        #expect(simulation.watchSummary().decision == nil)
    }

    // MARK: - A quiet colony

    @Test("A colony with nothing to decide says so")
    func quietColonyCarriesNoDecision() {
        let summary = quiet().watchSummary()
        #expect(summary.decision == nil)
        #expect(summary.hasDecision == false)
    }

    // MARK: - The payload

    /// A watch that has not been updated, or a complication entry written
    /// before this release, sends and reads a summary with no `decision` key.
    /// `WatchSummary` is synthesised-`Codable` and this is an optional, so the
    /// key is decoded with `decodeIfPresent` and its absence is nil rather
    /// than a thrown error — but that is a property of the compiler's
    /// synthesis, not of anything written down here, so it is worth a test.
    /// `World.init(from:)` exists because the same assumption was wrong once.
    @Test("A payload from before decisions existed still decodes")
    func olderPayloadDecodes() throws {
        let encoded = try JSONEncoder().encode(besieged().watchSummary())
        var fields = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(fields["decision"] != nil, "the fixture should have something to remove")
        fields.removeValue(forKey: "decision")

        let older = try JSONSerialization.data(withJSONObject: fields)
        let decoded = try JSONDecoder().decode(WatchSummary.self, from: older)

        #expect(decoded.decision == nil)
        #expect(decoded.hasDecision == false)
        #expect(decoded.population > 0, "the rest of the payload should be intact")
    }

    @Test("A decision survives the round trip it is sent over")
    func decisionRoundTrips() throws {
        let summary = besieged().watchSummary(now: epoch)
        let decoded = try JSONDecoder().decode(
            WatchSummary.self, from: JSONEncoder().encode(summary)
        )
        #expect(decoded == summary)
        #expect(decoded.decision?.options.count == 2)
    }
}
