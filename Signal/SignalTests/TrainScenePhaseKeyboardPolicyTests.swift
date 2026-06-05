import SwiftUI
import XCTest
@testable import Signal

final class TrainScenePhaseKeyboardPolicyTests: XCTestCase {
    func testShouldReleaseSetFieldFocusOnlyOnBackground() {
        XCTAssertFalse(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .inactive))
        XCTAssertTrue(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .background))
    }

    func testShouldNotReleaseSetFieldFocusOnActive() {
        XCTAssertFalse(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .active))
    }
}
