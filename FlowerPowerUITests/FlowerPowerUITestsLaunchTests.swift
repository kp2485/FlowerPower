//
//  FlowerPowerUITestsLaunchTests.swift
//  FlowerPowerUITests
//
//  A screenshot of the first screen, once per interface configuration.
//
//  This is not really a test and is kept anyway, because what it produces is
//  useful: `runsForEachTargetApplicationUIConfiguration` runs it again for
//  each configuration the scheme is set up for — light and dark, and any
//  localisation once there is more than one — and attaches what the app looks
//  like. Since none of the interface has ever been compiled, let alone looked
//  at, the first run of this is the first time anybody will see the app at
//  all.
//
//  It asserts the one thing a screenshot cannot: that the app was still in
//  the foreground when the picture was taken. An attachment of a crashed
//  app's last frame would otherwise pass silently.
//
//  Never run. See SETUP.md.
//

import XCTest

final class FlowerPowerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(app.state, .runningForeground)
    }
}
