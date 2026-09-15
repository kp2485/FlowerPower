//
//  FlowerPowerUITests.swift
//  FlowerPowerUITests
//
//  Does the app launch and get somewhere.
//
//  That is the whole of it, and it is deliberately the whole of it. What was
//  here before was Xcode's 2023 template: a `testExample` that launched the
//  app and asserted nothing, which passes whatever the app does. A test that
//  cannot fail is worse than no test, because it reports green.
//
//  The one thing asserted is that the app reaches a screen. Which screen is
//  not something the test controls — a first run opens on the introduction,
//  whose first page is "A wild colony"; a run whose colony has died offers
//  "Begin Again"; and any other run shows the tab bar, whose first tab is
//  "Colony" — so any of those three counts, and the app has to still be in
//  the foreground when one of them arrives. A crash on launch, a blank window,
//  a hang in `catchUp`, or a save the store cannot read all fail this. Nothing
//  else does, and nothing else is claimed.
//
//  The first run used to be listed as "A New Colony", the site chooser. That
//  was true until the introduction was put in front of it, and the first time
//  this test ran — on a fresh simulator, 2026-09-14 — it failed for exactly
//  that reason. The site chooser is never where a launch lands now: nothing is
//  saved until a site is chosen, so every launch before then starts the
//  introduction again from its first page.
//
//  It runs against whatever colony happens to be on the simulator, which is
//  the honest thing for a launch test to do and also its limitation: there is
//  no launch argument for starting from a known save. That is the first thing
//  any test wanting to drive the interface will have to add.
//
//  First run on 2026-09-14, on an iOS 26.5 simulator with the deployment
//  target overridden; see SETUP.md.
//

import XCTest

final class FlowerPowerUITests: XCTestCase {

    /// The three places a launch can legitimately land.
    private static let landings = ["Colony", "A wild colony", "Begin Again"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// On the main actor because `XCUIApplication` is, as in Xcode's own
    /// template. Without it the first Mac build warned at every call.
    @MainActor
    func testLaunchReachesAScreen() throws {
        let app = XCUIApplication()
        app.launch()

        // Matched across every element type rather than `staticTexts`,
        // because "Colony" is a tab bar button's label while the other two are
        // navigation titles, and which of those the accessibility tree calls a
        // static text is not something to bet a test on.
        let landed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", Self.landings))
            .firstMatch

        XCTAssertTrue(
            landed.waitForExistence(timeout: 20),
            "The app launched but showed none of \(Self.landings)."
        )

        // Still running, rather than having shown something and then died.
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
