import XCTest
@testable import Signal

final class CoachThreadCompactorTests: XCTestCase {
    func testTrimmedMessagesKeepsSummaryAndLastPair() {
        let messages = [
            ChatMessage(role: .user, text: "What should I train today?"),
            ChatMessage(role: .assistant, text: "Upper push with bench."),
            ChatMessage(role: .user, text: "Only 45 minutes."),
            ChatMessage(role: .assistant, text: "Drop shoulders, keep bench."),
        ]

        let trimmed = CoachThreadCompactor.trimmedMessages(
            summary: "Athlete wants upper push; later capped at 45 minutes without shoulders.",
            from: messages
        )

        XCTAssertEqual(trimmed.count, 3)
        XCTAssertTrue(trimmed[0].isCompactSummary)
        XCTAssertEqual(trimmed[1].text, "Only 45 minutes.")
        XCTAssertEqual(trimmed[2].text, "Drop shoulders, keep bench.")
    }

    func testTrimmedMessagesWithSingleExchange() {
        let messages = [
            ChatMessage(role: .user, text: "Hello"),
            ChatMessage(role: .assistant, text: "Hi"),
        ]

        let trimmed = CoachThreadCompactor.trimmedMessages(summary: "Greeting.", from: messages)

        XCTAssertEqual(trimmed.count, 3)
        XCTAssertTrue(trimmed[0].isCompactSummary)
    }

    func testTranscriptTextIgnoresCompactSummary() {
        let messages = [
            ChatMessage(role: .assistant, text: "Old summary", isCompactSummary: true),
            ChatMessage(role: .user, text: "Follow up"),
            ChatMessage(role: .assistant, text: "Reply"),
        ]

        let text = CoachTranscriptText.fromMessages(messages)
        XCTAssertFalse(text.contains("Old summary"))
        XCTAssertTrue(text.contains("Follow up"))
        XCTAssertTrue(text.contains("Reply"))
    }
}
