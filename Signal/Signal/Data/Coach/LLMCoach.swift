import Foundation

enum CoachError: Error, Sendable {
    case busy
    case contextTooLarge
    case rateLimited
    case compactionFailed
    case generationFailed(underlying: Error)
}

protocol LLMCoach: Sendable {
    func prewarm() async
    func respond(
        to query: String,
        context: CoachContext,
        threadKind: CoachThreadKind
    ) async throws -> AsyncThrowingStream<String, Error>
    func resetThread() async
    func abandonActiveWork() async
    func compactThread(messages: [ChatMessage]) async throws -> CoachCompactResult
    var contextUsage: CoachContextUsageSnapshot { get async }
    func contextUsage(nextPrompt: String) async -> CoachContextUsageSnapshot
    func hasActiveThread() async -> Bool
    func threadRoute() async -> CoachQueryRoute?
    var isResponding: Bool { get async }
}

extension LLMCoach {
    func respond(to query: String, context: CoachContext) async throws -> AsyncThrowingStream<String, Error> {
        try await respond(to: query, context: context, threadKind: .newThread)
    }
}
