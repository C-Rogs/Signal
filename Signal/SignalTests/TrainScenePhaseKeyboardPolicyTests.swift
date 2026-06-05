import SwiftUI
import XCTest
@testable import Signal

final class TrainScenePhaseKeyboardPolicyTests: XCTestCase {
    func testShouldReleaseSetFieldFocusOnInactiveAndBackground() {
        XCTAssertTrue(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .inactive))
        XCTAssertTrue(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .background))
    }

    func testShouldNotReleaseSetFieldFocusOnActive() {
        XCTAssertFalse(TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: .active))
    }

    func testShouldDismissKeyboardOnResumeOnlyWhenActive() {
        XCTAssertTrue(TrainScenePhaseKeyboardPolicy.shouldDismissKeyboardOnResume(for: .active))
        XCTAssertFalse(TrainScenePhaseKeyboardPolicy.shouldDismissKeyboardOnResume(for: .inactive))
        XCTAssertFalse(TrainScenePhaseKeyboardPolicy.shouldDismissKeyboardOnResume(for: .background))
    }
}
