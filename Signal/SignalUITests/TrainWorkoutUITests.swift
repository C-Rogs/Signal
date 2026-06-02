import XCTest

final class TrainWorkoutUITests: XCTestCase {
    @MainActor
    func testStartWorkoutAndDiscard() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Train"].tap()
        app.buttons["startWorkoutButton"].tap()

        XCTAssertTrue(app.buttons["finishWorkoutButton"].waitForExistence(timeout: 5))

        app.buttons["Discard"].tap()
        let discard = app.buttons["Discard"].firstMatch
        if discard.waitForExistence(timeout: 2) {
            discard.tap()
        }

        XCTAssertTrue(app.buttons["startWorkoutButton"].waitForExistence(timeout: 5))
    }
}
