import XCTest
@testable import FlowerPowerCore

/// Varroa dynamics.
///
/// Varroa is the single most important pathogen in the model, because it is the
/// leading cause of real colony loss. These tests exist because for a long time
/// it was not a cause of loss here at all: it arrived at its seed level, was
/// removed faster than it could breed, and twenty-four test colonies over 400
/// days recorded zero disease deaths.
final class VarroaTests: XCTestCase {

    /// Seeds varroa directly and reports the level day by day.
    private func trajectory(
        days: Int,
        config: SimulationConfig = .standard,
        seed: UInt64 = 42
    ) -> [Double] {
        var simulation = Fixture.thrivingSimulation(config: config, seed: seed)
        simulation.world.hive.pathogens[.varroa] = config.pathogenSeedLevel

        var levels: [Double] = []
        for _ in 0..<days {
            _ = simulation.stepDay()
            levels.append(simulation.world.hive.pathogens[.varroa])
        }
        return levels
    }

    /// Mite populations grow while there is capped brood to breed in. A colony
    /// that never accumulates mites cannot die of them, which is what made
    /// disease a non-event in the balance figures.
    func testVarroaGrowsInABroodRearingColony() {
        let levels = trajectory(days: 120)
        let start = levels.first ?? 0
        let peak = levels.max() ?? 0

        XCTAssertGreaterThan(
            peak, start * 2,
            "varroa should more than double over 120 days of brood rearing, "
            + "went \(start) -> \(peak)"
        )
    }

    /// Left alone it should build toward a level that threatens the colony,
    /// rather than sitting harmlessly at its seed value forever.
    ///
    /// Deliberately not asserting that it crosses the virus threshold inside a
    /// single year. Untreated colonies typically die of varroa in their second
    /// or third season, not their first, and the measured trajectory matches
    /// that: roughly 0.24 by day 300, crossing 0.3 during the second year.
    func testVarroaBuildsTowardDamagingLevels() {
        let levels = trajectory(days: 300)
        let peak = levels.max() ?? 0

        XCTAssertGreaterThan(
            peak, 0.15,
            "varroa should build substantially over a season, peaked at \(peak)"
        )
        XCTAssertLessThan(
            peak, PathogenLoad.varroaVirusThreshold,
            "varroa should not reach the virus threshold within a single year, "
            + "peaked at \(peak)"
        )
    }

    /// Hygienic stock should slow varroa markedly — but never eliminate it,
    /// because roughly half the mites are phoretic and out of reach.
    func testHygienicBehaviourSlowsButDoesNotClearVarroa() {
        var hygienic = SimulationConfig.standard
        hygienic.hygienicRemovalRate = SimulationConfig.standard.hygienicRemovalRate * 3

        let normal = trajectory(days: 200).max() ?? 0
        let cleaned = trajectory(days: 200, config: hygienic).max() ?? 0

        XCTAssertLessThan(cleaned, normal, "more hygiene should mean fewer mites")
        XCTAssertGreaterThan(
            cleaned, 0.0001,
            "hygiene should not clear varroa outright; phoretic mites are out of reach"
        )
    }
}
