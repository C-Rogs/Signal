import XCTest
@testable import Signal

final class CoachFollowUpToolsTests: XCTestCase {
    func testMergedRoutePromotesScheduleClarification() {
        let route = CoachSessionFactory.mergedRoute(
            pinnedRoute: .schedule,
            query: "what are the titles"
        )
        XCTAssertEqual(route, .schedule)
    }

    func testScheduleClarificationAddsCalendarTool() {
        let names = CoachSessionFactory.toolNames(
            modelContainer: try! SignalModelContainer.make(inMemoryOnly: true),
            query: "what are the titles",
            route: .schedule
        )
        XCTAssertTrue(names.contains("calendarSchedule"))
        XCTAssertTrue(names.contains("getDeviceClock"))
    }

    func testWorkoutThreadDoesNotAddCalendarToolForUnrelatedFollowUp() {
        let names = CoachSessionFactory.toolNames(
            modelContainer: try! SignalModelContainer.make(inMemoryOnly: true),
            query: "drop shoulders from the plan",
            route: .workoutPrescription
        )
        XCTAssertFalse(names.contains("calendarSchedule"))
    }
}
