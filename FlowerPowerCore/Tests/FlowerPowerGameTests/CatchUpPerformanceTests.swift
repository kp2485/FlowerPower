import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// How long it takes to catch a colony up after an absence.
///
/// This is not idle curiosity. `SimClock.maxCatchUpDays` is a ceiling on how
/// much time a single catch-up will simulate, and anything past it is skipped
/// rather than lived through — the colony is silently teleported forward. The
/// ceiling therefore decides how long a player can put the game down before it
/// starts lying to them, and the only thing that should set it is how much the
/// engine can actually chew through.
///
/// The budget matters most in the watch's widget extension, which has far less
/// of everything than a phone and is killed rather than slowed if it overruns.
/// The numbers here come from a desktop, so they are an optimistic bound;
/// the assertions are loose enough to survive much slower hardware and exist to
/// catch a system that becomes accidentally quadratic, which has happened once
/// already (`performs()` used to allocate a Set per call).
final class CatchUpPerformanceTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func colony(patches: Int = 8) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(
                coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                type: .livingTreeCavity
            ),
            startingAt: epoch,
            seed: 31
        )
        let species = FlowerCatalogue.all
        for index in 0..<patches {
            simulation.registerPhotograph(
                photoLocalIdentifier: "bench-\(index)",
                species: species[index % species.count],
                confidence: 0.8,
                coordinate: GeoPoint(latitude: 51.507 + Double(index) * 0.001,
                                     longitude: -0.127),
                takenAt: epoch
            )
        }
        return simulation
    }

    /// Seconds spent catching up over `days` of backlog.
    @discardableResult
    private func timeCatchUp(days: Int) -> Double {
        var simulation = colony()
        simulation.catchUpCeilingDays = max(days, simulation.catchUpCeilingDays)

        let target = epoch.addingTimeInterval(
            Double(days) * 24 * SimClock.defaultRealSecondsPerTick
        )

        let started = Date()
        let report = simulation.advance(to: target)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(report.daysSimulated, days, "the whole backlog should be simulated")
        print(String(format: "catch-up %4d days: %6.1f ms", days, elapsed * 1000))
        return elapsed
    }

    /// The ceiling the game actually ships with. A player who puts the phone
    /// down for a fortnight must not be teleported.
    func testCatchingUpTheFullCeilingIsFastEnoughForAWidget() {
        let elapsed = timeCatchUp(days: SimClock.defaultMaxCatchUpDays)

        XCTAssertLessThan(
            elapsed, 5.0,
            "a full-ceiling catch-up has to finish inside a widget's budget, "
            + "with room for hardware far slower than this"
        )
    }

    /// Cost should track the number of ticks, not something worse. A colony is
    /// bigger at 360 days than at 90, so some growth is expected; an order of
    /// magnitude is not.
    func testCatchUpCostGrowsRoughlyWithElapsedTime() {
        let short = timeCatchUp(days: 45)
        let long = timeCatchUp(days: 360)

        // Eight times the days. Allow forty times the cost before calling it
        // a regression — the point is to catch quadratic behaviour, not to
        // pin down a constant that varies with the machine.
        XCTAssertLessThan(
            long, max(short, 0.001) * 40,
            "catch-up cost should scale with ticks, not worse"
        )
    }
}
