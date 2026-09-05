import XCTest
@testable import FlowerPowerCore

/// Photographed patches fade.
///
/// This is the mechanism that makes the premise of the game true. Before it
/// existed, forage saturated: measured across patch counts, every result from
/// five photographs upward was byte-identical, because intake is clamped to
/// free comb and patches regrew to full capacity for ever. A player could
/// photograph five flowers on the first afternoon and never usefully take
/// another picture. The game is *about* photographing flowers.
final class PatchFadingTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func patch(registeredOn day: Int) -> FlowerPatch {
        FlowerPatch(
            id: EntityID(rawValue: 1),
            photoLocalIdentifier: "p",
            species: Fixture.clover,
            identificationConfidence: 1,
            discoveredAt: epoch,
            registeredOnDay: day
        )
    }

    // MARK: - The curve

    func testAFreshPatchIsAtFullStrength() {
        XCTAssertEqual(patch(registeredOn: 0).vigour(onDay: 0, config: .standard), 1)
    }

    func testAPatchHoldsFullStrengthThroughItsFreshPeriod() {
        let config = SimulationConfig.standard
        let subject = patch(registeredOn: 0)

        XCTAssertEqual(subject.vigour(onDay: config.patchFreshDays, config: config), 1,
                       "it should not start going before the fresh period is up")
    }

    func testAPatchDeclinesAfterItsFreshPeriod() {
        let config = SimulationConfig.standard
        let subject = patch(registeredOn: 0)

        let halfWayThroughFading = config.patchFreshDays + config.patchFadeDays / 2
        let vigour = subject.vigour(onDay: halfWayThroughFading, config: config)

        XCTAssertEqual(vigour, 0.5, accuracy: 0.02,
                       "fading should be linear across the fade period")
    }

    func testAPatchIsGoneAtTheEndOfTheFadePeriod() {
        let config = SimulationConfig.standard
        let subject = patch(registeredOn: 0)
        let gone = config.patchFreshDays + config.patchFadeDays

        XCTAssertEqual(subject.vigour(onDay: gone, config: config), 0)
        XCTAssertTrue(subject.hasFaded(onDay: gone, config: config))
        XCTAssertTrue(subject.hasFaded(onDay: gone + 500, config: config),
                      "and it does not come back")
    }

    /// Patches saved before fading existed carry no registration day. They are
    /// grandfathered rather than given a fabricated one, which would date them
    /// to day zero and wipe out an existing player's whole garden on upgrade.
    func testAPatchWithNoRegistrationDayNeverFades() {
        let old = FlowerPatch(
            id: EntityID(rawValue: 2),
            photoLocalIdentifier: "legacy",
            species: Fixture.clover,
            discoveredAt: epoch
        )

        XCTAssertNil(old.registeredOnDay)
        XCTAssertEqual(old.vigour(onDay: 10_000, config: .standard), 1)
    }

    // MARK: - What it does to the colony

    func testRegrowthIsCappedByTheFadedStand() {
        let config = SimulationConfig.standard
        var subject = patch(registeredOn: 0)
        let day = config.patchFreshDays + config.patchFadeDays / 2

        // Strip it, then let it regrow for a long time at the faded ceiling.
        _ = subject.harvest(nectar: 10_000, pollen: 10_000)
        for _ in 0..<200 { subject.regrow(rate: 0.5, onDay: day, config: config) }

        XCTAssertEqual(
            subject.remainingNectar,
            subject.nectarCapacity * 0.5,
            accuracy: subject.nectarCapacity * 0.05,
            "a half-faded stand should refill to half of what it once held"
        )
    }

    /// A patch that faded while the player was away must be brought *down* to
    /// its new ceiling, not left sitting on forage that is no longer there.
    func testAStandThatFadedWhileFullIsBroughtDown() {
        let config = SimulationConfig.standard
        var subject = patch(registeredOn: 0)
        XCTAssertEqual(subject.remainingNectar, subject.nectarCapacity)

        let day = config.patchFreshDays + config.patchFadeDays / 2
        subject.regrow(rate: 0.01, onDay: day, config: config)

        XCTAssertLessThan(subject.remainingNectar, subject.nectarCapacity * 0.6)
    }

    func testScoutsRateAFadingStandBelowAFreshOne() {
        let config = SimulationConfig.standard
        let fresh = patch(registeredOn: 100)
        let fading = patch(registeredOn: 0)
        let day = 100 + config.patchFreshDays + config.patchFadeDays / 2

        XCTAssertGreaterThan(
            fresh.forageQuality(onDay: day, config: config),
            fading.forageQuality(onDay: day, config: config),
            "the waggle dance should prefer the stand that is actually there"
        )
    }

    // MARK: - Registration

    func testRegisteringAPhotographStampsTheCurrentDay() {
        var simulation = Fixture.barrenSimulation()
        simulation.clock = SimClock(epoch: epoch, tick: 42 * SimClock.ticksPerDay)

        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: "today",
            species: Fixture.clover,
            confidence: 1,
            coordinate: nil,
            takenAt: epoch
        )

        XCTAssertEqual(patch.registeredOnDay, 42)
    }

    /// The whole point: a colony given one round of flowers and never another
    /// runs out, where before it was supplied for ever.
    func testAColonyStopsBeingFedIfThePlayerStopsPhotographing() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 5)
        for index in 0..<8 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "p\(index)",
                species: FlowerCatalogue.all[index % FlowerCatalogue.all.count],
                confidence: 0.9,
                coordinate: nil,
                takenAt: epoch,
                distanceMetres: 500
            )
        }

        let config = SimulationConfig.standard
        let allGone = config.patchFreshDays + config.patchFadeDays + 5
        for _ in 0..<allGone { _ = simulation.stepDay() }

        let stillWorkable = simulation.patches.contains {
            !$0.hasFaded(onDay: simulation.day, config: config)
        }
        XCTAssertFalse(stillWorkable, "every stand should have gone over by now")
    }
}
