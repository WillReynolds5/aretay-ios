//
//  AretayUITests.swift
//  AretayUITests
//

import XCTest

final class AretayUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInScreenAppears() throws {
        let app = XCUIApplication()
        app.launch()
        // App starts on the sign-in screen until a session exists.
        XCTAssertTrue(
            app.buttons["signInWithAppleButton"].waitForExistence(timeout: 5),
            "Sign in with Apple button should be visible on launch"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
