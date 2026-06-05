import Foundation

enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
}

enum FeedbackRating: String, Sendable, Codable {
    case thumbsUp
    case thumbsDown
}

struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: MessageRole
    var text: String
    let timestamp: Date
    var feedbackRating: FeedbackRating?
    var promptQuery: String?
    var isCompactSummary: Bool
    var isSystemNotice: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        timestamp: Date = Date(),
        feedbackRating: FeedbackRating? = nil,
        promptQuery: String? = nil,
        isCompactSummary: Bool = false,
        isSystemNotice: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.feedbackRating = feedbackRating
        self.promptQuery = promptQuery
        self.isCompactSummary = isCompactSummary
        self.isSystemNotice = isSystemNotice
    }
}
