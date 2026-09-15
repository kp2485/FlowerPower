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
//  no launch argument for starting from a known save. The second test drives
//  the interface anyway, by accepting either landing — it walks the
//  introduction if that is what appears, and goes straight on if the tabs are
//  already there.
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

    /// The tabs the game has, and the capture sheet opening with nothing in
    /// front of it.
    ///
    /// Two things this holds. The tab bar is Colony, Nest and Garden — the
    /// Forage map went with location on 2026-09-15, and a tab that came back
    /// would be a regression. And tapping the camera button opens the sheet
    /// with no system dialogue between the tap and "Choose a Photo": that is
    /// where the location prompt used to appear, and the app asks for no
    /// location now. The dialogue, if there were one, would belong to
    /// SpringBoard rather than the app, which is where the test looks.
    @MainActor
    func testTheTabsAreColonyNestGardenAndCaptureAsksForNoLocation() throws {
        let app = XCUIApplication()
        app.launch()

        let landed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", Self.landings))
            .firstMatch
        XCTAssertTrue(landed.waitForExistence(timeout: 20))

        // A first run: three pages of introduction, then the notification
        // page, declined here so that no system prompt gets in the way.
        if landed.label == "A wild colony" {
            for _ in 0..<3 { app.buttons["Next"].tap() }
            app.buttons["Not Now"].tap()
        }

        // A first run and a collapsed colony both end at the site chooser.
        let settle = app.buttons["Settle Here"]
        if settle.waitForExistence(timeout: 5) { settle.tap() }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "No tab bar appeared.")
        for tab in ["Colony", "Nest", "World", "Garden"] {
            XCTAssertTrue(tabBar.buttons[tab].exists, "The \(tab) tab is missing.")
        }
        XCTAssertFalse(tabBar.buttons["Forage"].exists, "The Forage tab was removed with the map.")

        // The World tab draws the generated ground; it must at least select
        // and stay standing with a colony that has no flowers yet.
        tabBar.buttons["World"].tap()
        XCTAssertTrue(tabBar.buttons["World"].isSelected)
        XCTAssertEqual(app.state, .runningForeground)
        tabBar.buttons["Colony"].tap()

        app.buttons["Photograph a Flower"].tap()
        let choose = app.buttons["Choose a Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "The capture sheet did not open.")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertEqual(springboard.alerts.count, 0, "A system prompt appeared in front of the capture sheet.")
        XCTAssertTrue(choose.isHittable)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
