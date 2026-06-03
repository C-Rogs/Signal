import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ChatFeedbackTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: ChatViewModel!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
        viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { _, _ in ChatTestFixtures.minimalContext },
            respond: { _, _ in ChatTestFixtures.singleChunkStream("Coach reply body") }
        )
    }

    func testThumbsUpStoresCorrectFields() async throws {
        viewModel.sendMessage("squat volume")
        try await waitForAssistantMessage()

        let assistantID = try XCTUnwrap(viewModel.messages.last?.id)
        viewModel.submitFeedback(messageID: assistantID, rating: .thumbsUp, modelContext: context)

        let rows = try context.fetch(FetchDescriptor<ChatFeedback>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].messageID, assistantID)
        XCTAssertEqual(rows[0].query, "squat volume")
        XCTAssertEqual(rows[0].rating, .thumbsUp)
        XCTAssertEqual(rows[0].responseExcerpt, "Coach reply body")
    }

    func testSecondTapUpdatesRatingWithoutDuplicateRow() async throws {
        viewModel.sendMessage("bench")
        try await waitForAssistantMessage()

        let assistantID = try XCTUnwrap(viewModel.messages.last?.id)
        viewModel.submitFeedback(messageID: assistantID, rating: .thumbsUp, modelContext: context)
        viewModel.submitFeedback(messageID: assistantID, rating: .thumbsDown, modelContext: context)

        let rows = try context.fetch(FetchDescriptor<ChatFeedback>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].rating, .thumbsDown)
        XCTAssertEqual(viewModel.messages.last?.feedbackRating, .thumbsDown)
    }

    private func waitForAssistantMessage() async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if viewModel.messages.contains(where: { $0.role == .assistant }) {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for assistant message")
    }
}
