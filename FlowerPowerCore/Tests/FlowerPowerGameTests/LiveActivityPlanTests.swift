//
//  LiveActivityPlanTests.swift
//  FlowerPowerGameTests
//
//  A card on the lock screen is for the part of an event that wants the
//  player, not for the event. These hold that line: up while there is
//  something to decide, down the moment it is decided, and never up for longer
//  than a simulated day — about two real hours — however long the skunk stays.
//

import Testing
import Foundation
@testable import FlowerPowerCore
@testable import FlowerPowerGame

@Suite("Live Activity plan")
struct LiveActivityPlanTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func colony(_ arrange: (inout Simulation) -> Void = { _ in }) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 21
        )
        arrange(&simulation)
        return simulation
    }

    private func advance(_ simulation: inout Simulation, toDay day: Int) {
        while simulation.clock.day < day { simulation.clock.commitTick() }
    }

    private func plan(_ simulation: Simulation) -> LiveActivityPlan {
        LiveActivityPlan(snapshot: simulation.snapshot())
    }

    // MARK: - Quiet

    @Test("A quiet colony puts nothing on the lock screen")
    func quietColony() {
        #expect(plan(colony()).items.isEmpty)
    }

    // MARK: - A siege

    @Test("A new siege nobody has answered gets a card, for one simulated day")
    func newSiege() throws {
        let simulation = colony {
            $0.world.activeThreat = ActiveThreat(predator: .skunk, beganOnDay: 0, resolvesOnDay: 3)
        }
        let item = try #require(plan(simulation).item(.siege))

        #expect(item.decisionOpen)
        #expect(item.title.contains(Predator.skunk.displayName))
        #expect(item.daysRemaining == 3)
        #expect(item.expiresOnDay == LiveActivityPlan.longestDays)
    }

    @Test("The card comes down the moment the siege is answered")
    func answeredSiege() throws {
        var simulation = colony {
            $0.world.activeThreat = ActiveThreat(predator: .skunk, beganOnDay: 0, resolvesOnDay: 3)
        }
        let threat = try #require(simulation.world.activeThreat)
        let answer = try #require(threat.options.first { $0 != .instinct })
        simulation.respond(to: threat, with: answer)

        #expect(plan(simulation).item(.siege) == nil)
    }

    @Test("A skunk that stays three days does not keep its card for three days")
    func longSiege() {
        var simulation = colony {
            $0.world.activeThreat = ActiveThreat(predator: .skunk, beganOnDay: 0, resolvesOnDay: 3)
        }
        advance(&simulation, toDay: 1)

        // The siege is still on and still unanswered — the decision is still
        // open on the dashboard — and the lock screen has let it go.
        #expect(simulation.world.activeThreat != nil)
        #expect(plan(simulation).item(.siege) == nil)
    }

    @Test("A siege with nothing to offer is announced, but asks nothing")
    func unanswerableSiege() throws {
        let simulation = colony {
            $0.world.activeThreat = ActiveThreat(predator: .bear, beganOnDay: 0, resolvesOnDay: 1)
        }
        let item = try #require(plan(simulation).item(.siege))
        #expect(!item.decisionOpen)
    }

    // MARK: - A swarm

    @Test("Swarm cells get a card until the player makes room")
    func swarm() throws {
        var simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        let item = try #require(plan(simulation).item(.swarm))
        #expect(item.decisionOpen)
        #expect(item.daysRemaining == 8)

        simulation.discourageSwarm()
        #expect(plan(simulation).item(.swarm) == nil)
    }

    @Test("A swarm that gathers for eight days does not keep its card for eight")
    func longSwarm() {
        var simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        advance(&simulation, toDay: 1)
        #expect(plan(simulation).item(.swarm) == nil)
    }

    // MARK: - A virgin queen

    /// Replaces whoever heads the colony with an unmated queen of a given age.
    /// A bee's days in its stage cannot be set from outside, so she is made
    /// afresh rather than edited.
    private func crownVirgin(_ simulation: inout Simulation, aged days: Int) {
        simulation.world.hive.bees.removeAll { $0.kind == BeeKind.queen }
        simulation.world.hive.bees.append(Bee(
            id: EntityID(rawValue: 90_001),
            kind: .queen, stage: .adult,
            daysInStage: days
        ))
        simulation.world.hive.queenIsMated = false
    }

    @Test("A virgin queen is announced on the day she emerges and not after")
    func virginQueen() throws {
        var simulation = colony()
        crownVirgin(&simulation, aged: 0)

        let item = try #require(plan(simulation).item(.matingFlight))
        #expect(!item.decisionOpen)
        #expect(item.expiresOnDay == simulation.clock.day + LiveActivityPlan.longestDays)

        crownVirgin(&simulation, aged: 3)
        #expect(plan(simulation).item(.matingFlight) == nil)
    }
}
