import XCTest
@testable import Signal

final class CoachContextBreakdownTests: XCTestCase {
    func testRowsIncludePendingPrompt() {
        var buckets = CoachContextBreakdown.CharBuckets()
        buckets.instructions = 700
        buckets.tools = 350
        buckets.turnOnePrompt = 3500
        buckets.conversation = 700
        buckets.toolOutputs = 350
        buckets.activeToolNames = ["calendarSchedule", "getDeviceClock"]
        let rows = CoachContextBreakdown.rows(from: buckets, pendingPromptChars: 140)
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows.contains { $0.label == "Next message" })
        XCTAssertTrue(rows.contains { $0.label == "Tools" })
    }

    func testBreakdownTokenSumIsConsistentWithSnapshot() {
        var buckets = CoachContextBreakdown.CharBuckets()
        buckets.instructions = 3500
        buckets.tools = 700
        buckets.turnOnePrompt = 7000
        buckets.conversation = 1400
        buckets.toolOutputs = 700
        buckets.activeToolNames = ["calendarSchedule"]
        let rows = CoachContextBreakdown.rows(from: buckets)
        let rowTotal = rows.reduce(0) { $0 + $1.estimatedTokens }
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 0,
            transcriptChars: buckets.total,
            nextPromptChars: 0,
            breakdown: rows,
            activeToolNames: buckets.activeToolNames
        )
        XCTAssertEqual(snapshot.estimatedTokens, rowTotal, accuracy: 5)
        XCTAssertEqual(snapshot.activeToolNames, ["calendarSchedule"])
    }
}
