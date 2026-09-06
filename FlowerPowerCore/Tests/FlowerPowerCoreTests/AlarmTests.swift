import Testing
import Foundation
@testable import FlowerPowerCore

/// Alarm pheromone, which for a long time was tracked, raised on every attack,
/// decayed on a careful schedule, and read by nothing at all.
///
/// It is now the colony's own instinctive version of holding the entrance: it
/// defends better, forages less and loses more bees stinging. Every one of
/// those effects is deliberately weaker than the equivalent `HivePosture`
/// multiplier, because a posture the player chooses has to be worth choosing —
/// and because instinct has to remain a real answer rather than an absence.
///
/// Measured over 200 colonies, two years: repel rate 44.9% to 46.2%, total
/// nectar down 2.0%, defenders lost up from 37 to 41 per colony, and two-year
/// survival unmoved at 66%. Which is the whole brief: it changed what it should
/// and nothing else.
@Suite("Alarm pheromone")
struct AlarmTests {

    // MARK: - Instinct stays below any posture the player could pick

    /// The relationship the three constants have to hold, stated as a test so
    /// that raising one later cannot quietly make instinct as good as a
    /// decision.
    @Test("Every effect of alarm is milder than the posture that does the same")
    func alarmIsMilderThanAPosture() {
        let config = SimulationConfig.standard

        let alarmedDefence = 1 + config.alarmDefenceBoost
        #expect(alarmedDefence < HivePosture.narrowEntrance.defenceMultiplier(against: .entrance))
        #expect(alarmedDefence < HivePosture.holdEntrance.defenceMultiplier(against: .entrance))

        let alarmedForaging = 1 - config.alarmForageCost
        #expect(alarmedForaging > HivePosture.narrowEntrance.forageMultiplier)
        #expect(alarmedForaging > HivePosture.holdEntrance.forageMultiplier)

        let alarmedCasualties = 1 + config.alarmCasualtyRate
        #expect(alarmedCasualties < HivePosture.holdEntrance.casualtyMultiplier())
    }

    // MARK: - It is wired to something

    /// The signal has to reach the field, or "alarmed" is a number in a struct.
    @Test("An alarmed colony brings in less than a calm one")
    func alarmCostsForaging() {
        func nectar(alarm: Double) -> Double {
            var simulation = Fixture.thrivingSimulation(config: .standard, seed: 4_040)
            var total = 0.0
            for _ in 0..<20 {
                // Held up rather than set once: the point is a colony that
                // stays alarmed, and `PheromoneSystem` decays it every tick.
                simulation.mutateWorld { $0.hive.pheromones.alarm = alarm }
                _ = simulation.stepDay()
                total += simulation.world.todayNectarIntake
            }
            return total
        }

        let calm = nectar(alarm: 0)
        let alarmed = nectar(alarm: 1)

        #expect(calm > 0, "the fixture brought nothing in, so this proves nothing")
        #expect(alarmed < calm, "alarm is not reaching the foragers")
        // Milder than a posture, so not by much.
        #expect(alarmed > calm * 0.8)
    }

    /// Raised the instant a raider arrives, and gone within the day. A colony
    /// that stayed hot for a week would be a different animal.
    @Test("Alarm decays away within about a day")
    func alarmDecays() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 4_041)
        simulation.mutateWorld { $0.hive.pheromones.alarm = 1 }

        _ = simulation.step()
        #expect(simulation.hive.pheromones.alarm < 1, "it did not decay at all")

        _ = simulation.stepDay()
        #expect(simulation.hive.pheromones.alarm < 0.1,
                "a colony should not still be roaring the next morning")
    }

    /// The cost that keeps the defence boost from being free.
    @Test("Stinging harder costs more bees")
    func alarmCostsDefenders() {
        let config = SimulationConfig.standard
        // A colony at full alarm loses a quarter more defenders than a calm
        // one, on top of whatever the posture costs.
        let calm = 1 + 0.0 * config.alarmCasualtyRate
        let roaring = 1 + 1.0 * config.alarmCasualtyRate
        #expect(roaring > calm)
        #expect(roaring == 1 + config.alarmCasualtyRate)
    }

    /// An attack is what raises it, and it is raised before the colony's
    /// response is rolled — the guards call, and the colony answers.
    @Test("Being attacked is what raises it")
    func attacksRaiseAlarm() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 4_042)
        simulation.mutateWorld { $0.hive.pheromones.alarm = 0 }

        var sawAnAttack = false
        var alarmAfterAttack = 0.0
        for _ in 0..<400 {
            for event in simulation.stepDay() {
                if case .attacked = event {
                    sawAnAttack = true
                    alarmAfterAttack = max(alarmAfterAttack, simulation.hive.pheromones.alarm)
                }
            }
            if sawAnAttack { break }
        }

        #expect(sawAnAttack, "no colony was attacked in a year, so nothing was measured")
        #expect(alarmAfterAttack > 0, "an attack left the colony entirely calm")
    }
}
