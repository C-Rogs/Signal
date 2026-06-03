import Foundation

enum CoachError: Error, Sendable {
    case busy
    case contextTooLarge
    case rateLimited
    case generationFailed(underlying: Error)
}

protocol LLMCoach: Sendable {
    func prewarm() async
    func respond(to query: String, context: CoachContext) async throws -> AsyncThrowingStream<String, Error>
    var isResponding: Bool { get async }
}
