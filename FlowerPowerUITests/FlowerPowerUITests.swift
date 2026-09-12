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
//  not something the test controls — a first run offers "A New Colony", a run
//  whose colony has died offers "Begin Again", and any other run shows the tab
//  bar, whose first tab is "Colony" — so any of those three counts, and the
//  app has to still be in the foreground when one of them arrives. A crash on
//  launch, a blank window, a hang in `catchUp`, or a save the store cannot
//  read all fail this. Nothing else does, and nothing else is claimed.
//
//  It runs against whatever colony happens to be on the simulator, which is
//  the honest thing for a launch test to do and also its limitation: there is
//  no launch argument for starting from a known save. That is the first thing
//  any test wanting to drive the interface will have to add.
//
//  **These have never been run.** There is no Mac in the loop that produced
//  them; they are written against XCTest from documentation and desk-checked.
//  See SETUP.md.
//

import XCTest

final class FlowerPowerUITests: XCTestCase {

    /// The three places a launch can legitimately land.
    private static let landings = ["Colony", "A New Colony", "Begin Again"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
