import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// When the game is allowed to interrupt someone.
///
/// Worth testing carefully because the failure mode is quiet and permanent:
/// notify about nothing and the player turns notifications off, after which
/// the game cannot tell them the one thing that actually matters.
final class ColonyNewsTests: XCTestCase {

    private func facts(
        _ status: ColonyStatus,
        headline: String = "Foraging steadily.",
        epitaph: String? = nil,
        alert: ColonyAlert? = nil,
        patches: Int = 6,
        inBloom: Int = 4
    ) -> ColonyNews.Facts {
        ColonyNews.Facts(
            status: status,
            headline: headline,
            epitaph: epitaph,
            criticalAlert: alert,
            patchCount: patches,
            patchesInBloom: inBloom
        )
    }

    private var criticalAlert: ColonyAlert {
        ColonyAlert(
            kind: .starving,
            severity: .critical,
            title: "The Colony Is Starving",
            detail: "There is almost nothing left to eat.",
            suggestion: "Photograph flowers in bloom nearby."
        )
    }

    // MARK: - Silence

    func testNothingIsSaidWhenNothingChanged() {
        let steady = facts(.steady)
        XCTAssertNil(ColonyNews.between(before: steady, after: steady))
    }

    func testNothingIsSaidWhenTheColonyImproves() {
        XCTAssertNil(
            ColonyNews.between(before: facts(.struggling), after: facts(.thriving)),
            "nobody needs waking to hear that things are fine"
        )
    }

    /// A decline is not automatically news. Thriving to steady is a colony
    /// having an ordinary week.
    func testNothingIsSaidForADeclineIntoAStateThatIsStillFine() {
        XCTAssertNil(ColonyNews.between(before: facts(.thriving), after: facts(.steady)))
    }

    func testNothingIsSaidWhenAlreadyStruggling() {
        let struggling = facts(.struggling)
        XCTAssertNil(
            ColonyNews.between(before: struggling, after: struggling),
            "a fortnight of struggling is not news every six hours"
        )
    }

    // MARK: - Worth saying

    func testADeclineIntoTroubleNamesTheProblem() throws {
        let news = try XCTUnwrap(ColonyNews.between(
            before: facts(.steady),
            after: facts(.critical, alert: criticalAlert)
        ))

        XCTAssertEqual(news.identifier, "alert-\(ColonyAlert.Kind.starving.rawValue)")
        XCTAssertEqual(news.title, "The Colony Is Starving")
        XCTAssertEqual(
            news.body, "Photograph flowers in bloom nearby.",
            "the suggestion is the useful half, so it should be what is shown"
        )
    }

    /// The most common decline now that patches fade, and the one the player
    /// fixes by going outside.
    func testRunningOutOfFlowersSaysSo() throws {
        let news = try XCTUnwrap(ColonyNews.between(
            before: facts(.steady),
            after: facts(.struggling, patches: 9, inBloom: 0)
        ))

        XCTAssertEqual(news.identifier, "no-forage")
        XCTAssertEqual(news.body, "The flowers you found have gone over. Photograph some more.")
    }

    func testNeverHavingPhotographedAnythingReadsDifferently() throws {
        let news = try XCTUnwrap(ColonyNews.between(
            before: facts(.steady),
            after: facts(.struggling, patches: 0, inBloom: 0)
        ))

        XCTAssertEqual(news.body, "Your bees have no flowers at all. Photograph some.")
    }

    // MARK: - The end

    func testCollapseIsAnnouncedWithItsCause() throws {
        let news = try XCTUnwrap(ColonyNews.between(
            before: facts(.critical),
            after: facts(.collapsed, epitaph: "The stores ran out before spring.")
        ))

        XCTAssertEqual(news.identifier, "collapsed")
        XCTAssertEqual(news.title, "The colony is gone")
        XCTAssertEqual(news.body, "The stores ran out before spring.")
    }

    /// Collapse is announced even though there is nothing to be done, because
    /// the alternative is the player discovering it days later by chance.
    func testCollapseIsAnnouncedEvenFromAlreadyCritical() {
        XCTAssertNotNil(
            ColonyNews.between(before: facts(.critical), after: facts(.collapsed))
        )
    }

    func testCollapseIsAnnouncedOnlyOnce() {
        let dead = facts(.collapsed, epitaph: "The colony dwindled away.")
        XCTAssertNil(
            ColonyNews.between(before: dead, after: dead),
            "a colony that was already gone is not news again"
        )
    }

    /// The identifier is what stops a fortnight of decline stacking a dozen
    /// notifications: the system replaces one carrying the same identifier.
    func testTheSameProblemKeepsTheSameIdentifier() {
        let before = facts(.steady)
        let after = facts(.critical, alert: criticalAlert)

        XCTAssertEqual(
            ColonyNews.between(before: before, after: after)?.identifier,
            ColonyNews.between(before: before, after: after)?.identifier
        )
    }

    // MARK: - Wiring

    /// The snapshot bridge has to pick out the *critical* alert, not merely
    /// the first one, or a routine notice would masquerade as an emergency.
    func testSnapshotFactsSelectTheCriticalAlert() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: Date(timeIntervalSince1970: 1_700_000_000),
            seed: 4
        )
        for _ in 0..<40 { _ = simulation.stepDay() }

        let snapshot = simulation.snapshot()
        let selected = snapshot.newsFacts.criticalAlert

        XCTAssertEqual(selected?.id, snapshot.alerts.first { $0.severity == .critical }?.id)
        XCTAssertEqual(snapshot.newsFacts.patchCount, snapshot.patches.count)
    }
}
