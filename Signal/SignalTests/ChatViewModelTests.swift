import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
    }

    func testUserMessageAppendedBeforeContextBuildCompletes() async throws {
        let gate = AsyncGate()
        let viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { query, _ in
                await gate.waitUntilReleased()
                return Self.minimalContext(for: query)
            },
            respond: { _, _ in
                Self.chunkStream(["Done"])
            }
        )

        viewModel.sendMessage("Hello")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].text, "Hello")
        XCTAssertTrue(viewModel.isThinking)

        await gate.release()
        try await waitUntil({ !$0.isThinking && $0.streamingText.isEmpty && $0.messages.count == 2 }, viewModel: viewModel)
    }

    func testIsThinkingFalseOnceStreamingStarts() async throws {
        let viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { query, _ in Self.minimalContext(for: query) },
            respond: { _, _ in
                Self.chunkStream(["A", "B"], delayBetweenChunks: 100_000_000)
            }
        )

        viewModel.sendMessage("Stream")
        try await waitUntil({ !$0.isThinking && !$0.streamingText.isEmpty }, viewModel: viewModel)
        XCTAssertFalse(viewModel.isThinking)
        XCTAssertFalse(viewModel.streamingText.isEmpty)
    }

    func testStreamingClearsAndAssistantAppendedOnComplete() async throws {
        let viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { query, _ in Self.minimalContext(for: query) },
            respond: { _, _ in Self.chunkStream(["Full reply"]) }
        )

        viewModel.sendMessage("Q")
        try await waitUntil({ $0.messages.count == 2 }, viewModel: viewModel)

        XCTAssertTrue(viewModel.streamingText.isEmpty)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertEqual(viewModel.messages.last?.text, "Full reply")
    }

    func testErrorPathClearsStreamingAndSetsErrorMessage() async throws {
        let viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { query, _ in Self.minimalContext(for: query) },
            respond: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: CoachError.rateLimited)
                }
            }
        )

        viewModel.sendMessage("Q")
        try await waitUntil({ $0.messages.count == 2 }, viewModel: viewModel)

        XCTAssertTrue(viewModel.streamingText.isEmpty)
        XCTAssertFalse(viewModel.isThinking)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.messages.last?.text, "Signal is cooling down. Try again in a moment.")
    }

    func testDoubleSendGuardReturnsEarly() async throws {
        let gate = AsyncGate()
        let viewModel = ChatViewModel(
            modelContainer: container,
            buildContext: { query, _ in
                await gate.waitUntilReleased()
                return Self.minimalContext(for: query)
            },
            respond: { _, _ in Self.chunkStream(["OK"]) }
        )

        viewModel.sendMessage("First")
        viewModel.sendMessage("Second")
        XCTAssertEqual(viewModel.messages.count, 1)

        await gate.release()
        try await waitUntil({ $0.messages.count == 2 }, viewModel: viewModel)
        XCTAssertEqual(viewModel.messages.first?.text, "First")
    }

    private nonisolated static func minimalContext(for query: String) -> CoachContext {
        ChatTestFixtures.minimalContext
    }

    private nonisolated static func chunkStream(
        _ chunks: [String],
        delayBetweenChunks: UInt64 = 0
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if delayBetweenChunks > 0 {
                        try? await Task.sleep(nanoseconds: delayBetweenChunks)
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private func waitUntil(
        _ predicate: @escaping (ChatViewModel) -> Bool,
        viewModel: ChatViewModel,
        timeoutSeconds: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if predicate(viewModel) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for view model state")
    }
}

private actor AsyncGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func waitUntilReleased() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
