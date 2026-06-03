import Foundation
import SwiftData

@Model
final class ChatFeedback {
    var id: UUID
    @Attribute(.unique) var messageID: UUID
    var query: String
    var responseExcerpt: String
    var ratingRaw: String
    var createdAt: Date

    var rating: FeedbackRating {
        get { FeedbackRating(rawValue: ratingRaw) ?? .thumbsUp }
        set { ratingRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        messageID: UUID,
        query: String,
        responseExcerpt: String,
        rating: FeedbackRating,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.query = query
        self.responseExcerpt = responseExcerpt
        self.ratingRaw = rating.rawValue
        self.createdAt = createdAt
    }
}
