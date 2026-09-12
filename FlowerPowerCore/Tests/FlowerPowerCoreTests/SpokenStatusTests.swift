import Testing
import Foundation
@testable import FlowerPowerCore

/// What Siri says about the colony.
///
/// Two kinds of assertion here, and the second is the one that matters. The
/// first is that each state produces the sentence it should — a siege names
/// the animal and the window, a full nest says what to do about it, a dead
/// colony gives its reason. The second is that nothing in the output is a
/// number nobody could say: the spoken answer is assembled from a snapshot
/// stuffed with `Double`s, and interpolating one of them by accident produces
/// "the colony is thriving, with 0.8734567 of its winter stores" — which is
/// not a bug any screen would ever have shown.
@Suite("Spoken status")
struct SpokenStatusTests {

    // MARK: - Fixtures

    /// A colony a month into its first spring, with no decision outstanding.
    ///
    /// The decisions are cleared rather than hoped absent: a month of
    /// simulation may or may not have produced a wasp, and a test about the
    /// ordinary sentence should not depend on which.
    private func healthySnapshot() -> ColonySnapshot {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(30)
        simulation.mutateWorld { world in
            world.activeThreat = nil
            world.pendingSwarm = nil
            world.lastSwarm = nil
        }
        return simulation.snapshot()
    }

    /// The same colony with a hornet at the door and two days to answer.
    private func siegeSnapshot(daysRemaining: Int = 2) -> ColonySnapshot {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(30)
        let today = simulation.clock.day
        simulation.mutateWorld { world in
            world.pendingSwarm = nil
            world.lastSwarm = nil
            world.activeThreat = ActiveThreat(
                predator: .hornet,
                beganOnDay: today,
                resolvesOnDay: today + daysRemaining
            )
        }
        return simulation.snapshot()
    }

    /// The comb drawn out to the walls of the cavity, with the cells in it
    /// occupied. The nest is shrunk to the colony rather than the colony grown
    /// into the nest, because the state wanted is a relationship between two
    /// numbers and this is the reliable way to arrange it.
    private func fullNestSnapshot() -> ColonySnapshot {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(30)
        simulation.mutateWorld { world in
            world.activeThreat = nil
            world.pendingSwarm = nil
            world.lastSwarm = nil
            world.hive.comb = Comb(workerCells: 20, droneCells: 0, capacity: 20)
        }
        return simulation.snapshot()
    }

    /// A colony with nothing left in it.
    private func collapsedSnapshot() -> ColonySnapshot {
        var simulation = Fixture.thrivingSimulation()
        simulation.runDays(30)
        simulation.mutateWorld { world in
            world.hive.bees.removeAll()
        }
        return simulation.snapshot()
    }

    // MARK: - The four states

    @Test("A healthy colony says what it is, how big it is and what it is doing")
    func healthy() {
        let snapshot = healthySnapshot()
        let spoken = snapshot.spokenStatus

        #expect(snapshot.status.isAlive)
        #expect(spoken.contains(snapshot.status.displayName.lowercased()))
        #expect(spoken.contains(snapshot.season.displayName.lowercased()))
        #expect(spoken.contains("bees"))
        // The colony's own headline is carried through rather than rewritten.
        #expect(spoken.contains(snapshot.headline))
        #expect(spoken.hasSuffix("."))
        #expect(!spoken.hasPrefix("Your bees are gone"))
    }

    @Test("A siege names what is at the nest and how long there is to answer")
    func siege() {
        let snapshot = siegeSnapshot(daysRemaining: 2)
        let spoken = snapshot.spokenStatus

        #expect(snapshot.activeThreat != nil)
        #expect(spoken.contains("Hornet at the nest"))
        #expect(spoken.contains("2 days to answer"))
    }

    @Test("A siege about to resolve does not offer days that are not there")
    func siegeOnItsLastDay() {
        let spoken = siegeSnapshot(daysRemaining: 0).spokenStatus
        #expect(spoken.contains("resolving today"))
        #expect(!spoken.contains("0 days"))

        let tomorrow = siegeSnapshot(daysRemaining: 1).spokenStatus
        #expect(tomorrow.contains("a day to answer"))
        #expect(!tomorrow.contains("1 days"))
    }

    @Test("A full nest says what to do about it")
    func fullNest() {
        let snapshot = fullNestSnapshot()
        let spoken = snapshot.spokenStatus

        // The precondition, asserted rather than assumed: this is the state
        // `ColonyNews` calls full, and the sentence is only right if the
        // fixture actually reached it.
        #expect(snapshot.nest.combOccupancy >= 0.9)
        #expect(snapshot.nest.builtCells >= snapshot.nest.capacity)
        #expect(snapshot.pendingSwarm == nil)

        #expect(spoken.contains("The nest is full"))
        // There is cavity left to give, so the answer is room rather than a
        // division.
        #expect(snapshot.canAddComb)
        #expect(spoken.contains("Open it up"))
    }

    @Test("A collapsed colony gives its reason and nothing else")
    func collapsed() throws {
        let snapshot = collapsedSnapshot()
        #expect(snapshot.status == .collapsed)

        // The whole answer, exactly: the reason and the way forward, with no
        // population, no season and no decision, because there is nothing
        // left to decide.
        let epitaph = try #require(snapshot.epitaph)
        #expect(snapshot.spokenStatus == "Your bees are gone. \(epitaph) "
                + "A new swarm is looking for somewhere to live.")
    }

    // MARK: - Sayable numbers

    @Test("Nothing spoken is an unrounded number")
    func noUnroundedNumbers() {
        for snapshot in [healthySnapshot(), siegeSnapshot(), fullNestSnapshot(), collapsedSnapshot()] {
            let spoken = snapshot.spokenStatus
            #expect(
                !Self.containsDecimalNumber(spoken),
                "a decimal reached the spoken answer: \(spoken)"
            )
            #expect(!spoken.contains("%"), "a percentage reached the spoken answer: \(spoken)")
        }
    }

    @Test("Bee counts are rounded by magnitude")
    func populationRounding() {
        // Nearest ten, hundred, thousand — and rounded rather than truncated,
        // which is what the last two cases are here to hold.
        #expect(ColonySnapshot.spokenRounding(of: 62) == 60)
        #expect(ColonySnapshot.spokenRounding(of: 347) == 350)
        #expect(ColonySnapshot.spokenRounding(of: 4_218) == 4_200)
        #expect(ColonySnapshot.spokenRounding(of: 12_640) == 13_000)
    }

    /// Under a hundred the exact figure is the interesting part — the
    /// difference between sixty bees and forty is the difference between a
    /// cluster and an ending — and above it nobody can hold the digits anyway.
    @Test("A small colony is counted exactly, a large one approximately")
    func populationWording() {
        let snapshot = healthySnapshot()
        let spoken = snapshot.spokenPopulation

        if snapshot.population.total < 100 {
            #expect(spoken == "\(snapshot.population.total) bees")
        } else {
            #expect(spoken.hasPrefix("about "))
        }
        #expect(spoken.hasSuffix("bees") || spoken == "one bee")
    }

    // MARK: - Helpers

    /// A digit, a full stop, a digit — which is how a `Double` gives itself
    /// away in prose. A full stop ending a sentence never has a digit after
    /// it, so this does not fire on ordinary punctuation.
    private static func containsDecimalNumber(_ text: String) -> Bool {
        let characters = Array(text)
        for index in characters.indices.dropFirst().dropLast()
        where characters[index] == "." {
            if characters[index - 1].isNumber, characters[index + 1].isNumber {
                return true
            }
        }
        return false
    }
}
