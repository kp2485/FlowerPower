import Testing
import Foundation
import FlowerPowerCore
@testable import FlowerPowerGame

/// The catch-up ceiling is part of the save, so raising the default does
/// nothing for a colony that already exists unless the save is lifted on the
/// way in. These hold the two halves of that: a ceiling an older build wrote
/// as its default is raised, and anything else is left as it was.
@Suite("Catch-up ceiling")
struct CatchUpCeilingTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func reopened(withCeiling days: Int) throws -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 5
        )
        simulation.catchUpCeilingDays = days
        return try GamePersistence.decodeTransfer(
            GamePersistence.encodeForTransfer(simulation)
        )
    }

    @Test("A year is the ceiling a new colony is given")
    func aYear() {
        #expect(SimClock.defaultMaxCatchUpDays == 365)
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 5
        )
        #expect(simulation.catchUpCeilingDays == 365)
    }

    @Test("A save carrying an older build's default is lifted to a year", arguments: [30, 180])
    func olderDefaultIsLifted(days: Int) throws {
        #expect(try reopened(withCeiling: days).catchUpCeilingDays == SimClock.defaultMaxCatchUpDays)
    }

    @Test("Any other ceiling is left as it was", arguments: [2, 90, 400])
    func otherCeilingsKept(days: Int) throws {
        #expect(try reopened(withCeiling: days).catchUpCeilingDays == days)
    }
}
