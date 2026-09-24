//
//  LiveActivityPlanTests.swift
//  FlowerPowerGameTests
//
//  A card on the lock screen is for the part of an event that wants the
//  player, and it should be doing something the whole time it is up. These
//  hold both lines: a question is on the card for a simulated day at most —
//  about two real hours — however long the skunk stays; an answer turns the
//  card into a countdown to the end of the siege, never past ActivityKit's
//  eight hours; and the end of the siege is said, not just stopped.
//
//  Dates are the colony's own. `now` is always the instant the simulation's
//  current tick began, so nothing here reads the wall clock.
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

    /// The instant the simulation's current tick began: "now", as far as the
    /// colony is concerned.
    private func now(_ simulation: Simulation) -> Date {
        simulation.clock.date(atTick: simulation.clock.tick)
    }

    private func day(_ day: Int, of simulation: Simulation) -> Date {
        LiveActivityPlan.date(ofDay: day, on: simulation.clock)
    }

    private func plan(_ simulation: Simulation) -> LiveActivityPlan {
        LiveActivityPlan(simulation: simulation, now: now(simulation))
    }

    /// Advances day by day until the real clock is at least `interval` past
    /// the start of day 0. Walked rather than computed, because winter days
    /// are shorter and a test should not care which season day 0 falls in.
    private func advance(_ simulation: inout Simulation, pastRealTime interval: TimeInterval) {
        let start = day(0, of: simulation)
        while now(simulation) < start.addingTimeInterval(interval) {
            advance(&simulation, toDay: simulation.clock.day + 1)
        }
    }

    private func skunk(resolvingOn resolves: Int = 3) -> Simulation {
        colony {
            $0.world.activeThreat = ActiveThreat(predator: .skunk, beganOnDay: 0, resolvesOnDay: resolves)
        }
    }

    private func answer(_ simulation: inout Simulation) throws -> HivePosture {
        let threat = try #require(simulation.world.activeThreat)
        let answer = try #require(threat.options.first { $0 != .instinct })
        simulation.respond(to: threat, with: answer)
        return answer
    }

    // MARK: - Quiet

    @Test("A quiet colony puts nothing on the lock screen")
    func quietColony() {
        #expect(plan(colony()).items.isEmpty)
    }

    // MARK: - A siege, deciding

    @Test("A new siege nobody has answered gets a card, with a clock to instinct's answer")
    func newSiege() throws {
        let simulation = skunk()
        let item = try #require(plan(simulation).item(.siege))

        #expect(item.phase == .deciding)
        #expect(item.decisionOpen)
        #expect(item.title.contains(Predator.skunk.displayName))
        #expect(item.event == .init(kind: .siege, startedOnDay: 0, predator: .skunk))

        // The clock runs to the end of the first day, and the card goes stale
        // with it; the siege itself runs on to day three.
        #expect(item.startedAt == day(0, of: simulation))
        #expect(item.deadline == day(LiveActivityPlan.longestDays, of: simulation))
        #expect(item.staleDate == item.deadline)
        #expect(item.resolvesAt == day(3, of: simulation))
    }

    @Test("The buttons are the notification's, in the notification's order")
    func siegeAnswers() throws {
        let simulation = skunk()
        let item = try #require(plan(simulation).item(.siege))
        let expected = HivePosture.options(against: Predator.skunk.attackStyle)
            .filter { $0 != .instinct }
            .map(DecisionAction.posture)

        #expect(!expected.isEmpty)
        #expect(item.answers == expected)
    }

    @Test("The siege card shows the guards and the alarm")
    func siegeScene() throws {
        let simulation = skunk()
        let snapshot = simulation.snapshot()
        let item = try #require(plan(simulation).item(.siege))

        #expect(item.scene.guards == (snapshot.population.jobs[.guardBee] ?? 0))
        #expect(item.scene.alarm == snapshot.alarm)
        #expect(item.symbol == Predator.skunk.symbolName)
        // Not known until the siege is settled, so not shown.
        #expect(item.scene.beesLost == nil)
    }

    @Test("A skunk that stays three days does not keep its question up for three days")
    func longSiege() {
        var simulation = skunk()
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
        #expect(item.phase == .deciding)
        #expect(item.answers.isEmpty)
        #expect(!item.decisionOpen)
    }

    @Test("A posture held from last week's swarm is no answer to this siege")
    func unrelatedPosture() throws {
        var simulation = skunk()
        simulation.world.posture = .makeRoom
        let item = try #require(plan(simulation).item(.siege))
        #expect(item.phase == .deciding)
        #expect(item.decisionOpen)
    }

    // MARK: - A siege, holding

    @Test("The card moves to holding when the siege is answered")
    func answeredSiege() throws {
        var simulation = skunk()
        let posture = try answer(&simulation)
        let item = try #require(plan(simulation).item(.siege))

        #expect(item.phase == .holding)
        #expect(item.answers.isEmpty)
        #expect(!item.decisionOpen)
        #expect(item.posture == posture.displayName)
        #expect(item.status == LiveActivityPlan.underWay(posture))

        // A three-day siege is six hours, inside ActivityKit's eight, so the
        // card lasts exactly as long as the siege does.
        #expect(item.deadline == item.resolvesAt)
        #expect(item.staleDate == item.resolvesAt)
        #expect(item.resolvesAt == day(3, of: simulation))
    }

    @Test("An answered siege keeps its card past the day an unanswered one loses it")
    func holdingOutlastsDeciding() throws {
        var simulation = skunk()
        _ = try answer(&simulation)
        advance(&simulation, toDay: 2)

        let item = try #require(plan(simulation).item(.siege))
        #expect(item.phase == .holding)
    }

    @Test("A holding card never outlasts ActivityKit's eight hours")
    func holdingCap() throws {
        // Longer than any siege the engine starts, so the cap is what ends it.
        var simulation = skunk(resolvingOn: 12)
        _ = try answer(&simulation)

        let item = try #require(plan(simulation).item(.siege))
        let cap = day(0, of: simulation).addingTimeInterval(LiveActivityPlan.longestActivity)
        #expect(item.staleDate == min(item.resolvesAt, cap))
        #expect(item.staleDate <= cap)

        advance(&simulation, pastRealTime: LiveActivityPlan.longestActivity)
        #expect(simulation.world.activeThreat != nil)
        #expect(plan(simulation).item(.siege) == nil)
    }

    @Test("A siege overdue at the turn of the day counts down to the next turn, not into the past")
    func overdueSiege() throws {
        var simulation = skunk(resolvingOn: 1)
        _ = try answer(&simulation)
        // The engine has not run, so the siege is still on past its day.
        advance(&simulation, toDay: 1)
        let item = try #require(plan(simulation).item(.siege))
        #expect(item.resolvesAt == day(2, of: simulation))
        #expect(item.resolvesAt > now(simulation))
    }

    // MARK: - A swarm

    @Test("Swarm cells get a card with the answers the engine would honour")
    func swarm() throws {
        let simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        let snapshot = simulation.snapshot()
        let item = try #require(plan(simulation).item(.swarm))

        #expect(item.phase == .deciding)
        #expect(item.decisionOpen)
        #expect(item.deadline == day(LiveActivityPlan.longestDays, of: simulation))
        #expect(item.resolvesAt == day(8, of: simulation))

        // Making room first, as the notification has it; opening the nest up
        // and dividing only where they would do something; letting them go
        // not at all, because it is what nobody answering already means.
        #expect(item.answers.first == .discourageSwarm)
        #expect(item.answers.contains(.addComb) == snapshot.swarmOffersComb)
        #expect(item.answers.contains(.split) == snapshot.canSplit)
        #expect(!item.answers.contains(.letSwarmGo))
    }

    @Test("The swarm card shows who is getting ready to go")
    func swarmScene() throws {
        let simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        let snapshot = simulation.snapshot()
        let item = try #require(plan(simulation).item(.swarm))

        #expect(item.scene.queenCells == snapshot.nest.queenCells.count)
        #expect(item.scene.departing == LiveActivityPlan.departing(
            snapshot, share: simulation.config.swarmDepartureShare
        ))
        #expect((item.scene.departing ?? 0) < snapshot.population.adults)
    }

    @Test("Making room moves the swarm card to holding")
    func discouragedSwarm() throws {
        var simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        simulation.discourageSwarm()

        let item = try #require(plan(simulation).item(.swarm))
        #expect(item.phase == .holding)
        #expect(item.answers.isEmpty)

        // Eight simulated days is sixteen real hours, which ActivityKit will
        // not allow; the card goes at eight.
        let cap = day(0, of: simulation).addingTimeInterval(LiveActivityPlan.longestActivity)
        #expect(item.staleDate == min(item.resolvesAt, cap))

        advance(&simulation, pastRealTime: LiveActivityPlan.longestActivity)
        #expect(simulation.world.pendingSwarm != nil)
        #expect(plan(simulation).item(.swarm) == nil)
    }

    @Test("A swarm that gathers for eight days does not keep its question up for eight")
    func longSwarm() {
        var simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8)
        }
        advance(&simulation, toDay: 1)
        #expect(plan(simulation).item(.swarm) == nil)
    }

    // MARK: - How it ended

    private func outcome(
        _ event: LiveActivityPlan.Event,
        _ simulation: Simulation
    ) -> LiveActivityPlan.Item? {
        LiveActivityPlan.outcome(
            for: event,
            in: simulation.snapshot(),
            attacks: simulation.world.attackHistory,
            now: now(simulation)
        )
    }

    private let skunkSiege = LiveActivityPlan.Event(kind: .siege, startedOnDay: 0, predator: .skunk)
    private let firstSwarm = LiveActivityPlan.Event(kind: .swarm, startedOnDay: 0)

    private func record(
        _ predator: Predator, day: Int, repelled: Bool,
        bees: Int = 0, stores: Double = 0, comb: Int = 0
    ) -> AttackRecord {
        AttackRecord(
            id: EntityID(rawValue: 80_000 + UInt64(day)),
            predator: predator, day: day, wasRepelled: repelled,
            beesLost: bees, storesLost: stores, combLost: comb
        )
    }

    @Test("A siege still on has no ending to tell")
    func siegeNotOver() {
        #expect(outcome(skunkSiege, skunk()) == nil)
    }

    @Test("A skunk driven off is said, with what it cost, for half an hour")
    func siegeRepelled() throws {
        var simulation = skunk()
        advance(&simulation, toDay: 3)
        simulation.world.activeThreat = nil
        simulation.world.attackHistory.append(record(.skunk, day: 3, repelled: true, bees: 12))

        let item = try #require(outcome(skunkSiege, simulation))
        #expect(item.phase == .resolved)
        #expect(item.event == skunkSiege)
        #expect(item.title.contains("driven off"))
        #expect(item.status.contains("12 defenders"))
        #expect(item.scene.beesLost == 12)
        #expect(item.scene.repelled == true)
        #expect(!item.decisionOpen)
        #expect(item.staleDate == now(simulation).addingTimeInterval(LiveActivityPlan.outcomeLingers))
    }

    @Test("A raid that got in lists what it took")
    func siegeLost() throws {
        var simulation = skunk()
        simulation.world.activeThreat = nil
        simulation.world.attackHistory.append(
            record(.skunk, day: 3, repelled: false, bees: 40, stores: 11.6, comb: 1)
        )

        let item = try #require(outcome(skunkSiege, simulation))
        #expect(item.scene.repelled == false)
        #expect(item.status == "40 bees lost, 12 honey taken and 1 cell of comb spoiled")
    }

    @Test("An old record, or somebody else's, is not this siege's ending")
    func siegeWrongRecord() {
        var simulation = colony {
            $0.world.activeThreat = nil
            $0.world.attackHistory = [
                AttackRecord(id: EntityID(rawValue: 1), predator: .skunk, day: 0,
                             wasRepelled: true, beesLost: 1, storesLost: 0, combLost: 0),
            ]
        }
        let later = LiveActivityPlan.Event(kind: .siege, startedOnDay: 5, predator: .skunk)
        #expect(outcome(later, simulation) == nil)

        simulation.world.attackHistory.append(record(.wasp, day: 7, repelled: true))
        #expect(outcome(later, simulation) == nil)
    }

    @Test("A different siege at the nest is not this one still going on")
    func siegeReplaced() throws {
        var simulation = colony {
            $0.world.activeThreat = ActiveThreat(predator: .wasp, beganOnDay: 4, resolvesOnDay: 6)
        }
        simulation.world.attackHistory.append(record(.skunk, day: 3, repelled: true))
        let item = try #require(outcome(skunkSiege, simulation))
        #expect(item.title.contains(Predator.skunk.displayName))
    }

    @Test("A swarm that went is said, with how many went")
    func swarmDeparted() throws {
        var simulation = colony()
        simulation.world.pendingSwarm = nil
        simulation.world.lastSwarm = DepartedSwarm(
            day: 6,
            queen: Bee(id: EntityID(rawValue: 90_002), kind: .queen, stage: .adult, daysInStage: 400),
            workers: [],
            genetics: simulation.world.hive.genetics,
            honeyCarried: 4,
            queenNumber: nil
        )

        let item = try #require(outcome(firstSwarm, simulation))
        #expect(item.phase == .resolved)
        #expect(item.title == "The colony has divided")
        #expect(item.scene.departing == 1)
    }

    @Test("A swarm that thought better of it is said too")
    func swarmCalledOff() throws {
        var simulation = colony()
        simulation.world.pendingSwarm = nil
        simulation.world.lastSwarm = nil

        let item = try #require(outcome(firstSwarm, simulation))
        #expect(item.title == "The swarm is off")
    }

    @Test("A swarm still gathering has no ending to tell")
    func swarmNotOver() {
        let simulation = colony {
            $0.world.pendingSwarm = PendingSwarm(startedOnDay: 0, departsOnDay: 8, discouraged: true)
        }
        #expect(outcome(firstSwarm, simulation) == nil)
    }

    // MARK: - Dates

    @Test("A simulated day's real start is found in the past as well as the future")
    func datesOfDays() {
        var simulation = colony()
        advance(&simulation, toDay: 2)
        let clock = simulation.clock

        #expect(day(0, of: simulation) == clock.epoch)
        #expect(day(2, of: simulation) == now(simulation))
        #expect(day(5, of: simulation) == clock.date(atTick: 5 * SimClock.ticksPerDay))
        #expect(day(1, of: simulation) < day(2, of: simulation))
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
        #expect(item.answers.isEmpty)
        #expect(item.staleDate == day(simulation.clock.day + LiveActivityPlan.longestDays, of: simulation))

        crownVirgin(&simulation, aged: 3)
        #expect(plan(simulation).item(.matingFlight) == nil)
    }

    @Test("Her card is an announcement, and ends without a last word")
    func virginQueenOutcome() {
        let event = LiveActivityPlan.Event(kind: .matingFlight, startedOnDay: 0)
        #expect(outcome(event, colony()) == nil)
    }
}
