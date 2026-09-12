import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// The record as the interface sees it.
///
/// `GameStore.history` is a computed property over the stored simulation
/// rather than a published copy, which is the cheap choice and only correct if
/// it actually keeps up with the colony. That is what this checks.
@Suite("Colony history through the store")
@MainActor
struct GameHistoryTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// 5 real minutes per simulated hour, as `SimClock` runs.
    private func makeStore(seed: UInt64 = 404) -> (GameStore, Box) {
        let clock = Box(now: epoch)
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: seed
        )
        return (
            GameStore(
                simulation: simulation,
                persistence: InMemoryPersistence(),
                clock: { clock.now }
            ),
            clock
        )
    }

    final class Box: @unchecked Sendable {
        var now: Date
        init(now: Date) { self.now = now }
        func advance(simulatedDays days: Double) {
            now = now.addingTimeInterval(days * 24 * 300)
        }
    }

    @Test("A colony nobody has caught up on has no record yet")
    func freshStoreHasNoHistory() {
        let (store, _) = makeStore()
        #expect(store.history.isEmpty)
    }

    @Test("The record follows the colony through a catch-up")
    func historyFollowsCatchUp() {
        let (store, clock) = makeStore()

        clock.advance(simulatedDays: 10)
        store.catchUp()

        let history = store.history
        #expect(history.samples.count == store.snapshot.day)
        #expect(history.lastDay == store.snapshot.day - 1)
        #expect(history.firstDay == 0)

        // And again, so the second catch-up is shown to extend the record
        // rather than replace it.
        clock.advance(simulatedDays: 5)
        store.catchUp()

        #expect(store.history.samples.count == store.snapshot.day)
        #expect(store.history.firstDay == 0)
        #expect(store.history.lastDay == store.snapshot.day - 1)
    }

    @Test("The record the store hands over is the colony's own numbers")
    func historyMatchesTheSnapshot() {
        let (store, clock) = makeStore()

        clock.advance(simulatedDays: 12)
        store.catchUp()

        // The newest sample was taken at the last day boundary, so it is the
        // colony as it stood that morning rather than right now — but the
        // things that do not change hour to hour should agree.
        guard let sample = store.history.samples.last else {
            Issue.record("the store handed over an empty record")
            return
        }
        #expect(sample.combCells == store.snapshot.nest.builtCells)
        #expect(sample.season == store.snapshot.season)
        #expect(sample.adults > 0)
    }

    @Test("A saved colony brings its record back")
    func historySurvivesASave() throws {
        let persistence = InMemoryPersistence()
        let clock = Box(now: epoch)
        let first = GameStore(
            simulation: Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity),
                startingAt: epoch,
                seed: 77
            ),
            persistence: persistence,
            clock: { clock.now }
        )

        clock.advance(simulatedDays: 6)
        first.catchUp()
        let recorded = first.history

        let reloaded = GameStore.load(persistence: persistence, clock: { clock.now })
        #expect(reloaded.history == recorded)
        #expect(!recorded.isEmpty)
    }
}
