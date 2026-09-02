//
//  RadioUITests.swift
//  RadioUITests
//

import XCTest

/// Radio is an `LSUIElement` menu-bar app: no dock icon, no main window, and the
/// panel is a borderless `NSPanel` at `.popUpMenu` level. That makes deep XCUITest
/// automation (clicking the status item, asserting on rows) unreliable until the
/// panel's controls get accessibility identifiers — see the roadmap's accessibility item.
/// Until then this stays a launch smoke test.
final class RadioUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndKeepsRunning() throws {
        let app = XCUIApplication()
        app.launch()

        // The app auto-opens its panel ~0.5s after launch; give it a beat, then
        // confirm the process is still alive (didn't crash on launch).
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertNotEqual(app.state, .notRunning)

        app.terminate()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
