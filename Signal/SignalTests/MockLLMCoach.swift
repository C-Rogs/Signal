import Foundation
import FoundationModels
import SwiftData
import os
@testable import Signal

actor MockLLMCoach: LLMCoach {
    var respondHandler: @Sendable (String, CoachContext, CoachThreadKind) async throws -> AsyncThrowingStream<String, Error>
    private(set) var isRespondingFlag = false

    init(
        respondHandler: @escaping @Sendable (String, CoachContext, CoachThreadKind) async throws -> AsyncThrowingStream<String, Error> = { _, _, _ in
            AsyncThrowingStream<String, Error> { $0.finish() }
        }
    ) {
        self.respondHandler = respondHandler
    }

    var isResponding: Bool {
        isRespondingFlag
    }

    func prewarm() async {}

    func respond(
        to query: String,
        context: CoachContext,
        threadKind: CoachThreadKind
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await respondHandler(query, context, threadKind)
    }

    func resetThread() async {}

    func compactThread(messages: [ChatMessage]) async throws -> CoachCompactResult {
        CoachCompactResult(summary: "summary", messages: messages)
    }

    var contextUsage: CoachContextUsageSnapshot {
        .empty
    }

    func contextUsage(nextPrompt: String) async -> CoachContextUsageSnapshot {
        .empty
    }

    func hasActiveThread() async -> Bool {
        false
    }

    func threadRoute() async -> CoachQueryRoute? {
        nil
    }
}
