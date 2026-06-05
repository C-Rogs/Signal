import XCTest
@testable import Signal

final class CoachQueryIntentTests: XCTestCase {
    func testScheduleClarificationWhenPinnedRouteIsSchedule() {
        XCTAssertTrue(
            CoachQueryIntent.needsScheduleAccess(
                query: "what are the titles",
                pinnedRoute: .schedule
            )
        )
    }

    func testScheduleClarificationFalseForUnrelatedThread() {
        XCTAssertFalse(
            CoachQueryIntent.needsScheduleAccess(
                query: "what are the titles",
                pinnedRoute: .workoutPrescription
            )
        )
    }

    func testCalendarQueryNeedsScheduleAccess() {
        XCTAssertTrue(
            CoachQueryIntent.needsScheduleAccess(
                query: "what's on my calendar today",
                pinnedRoute: .general
            )
        )
    }
}
