import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var title: String
    var sessionDescription: String?
    var startTime: Date
    var endTime: Date?
    var date: Date
    var source: String

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.session)
    var exercises: [WorkoutExercise] = []

    init(
        title: String,
        sessionDescription: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        date: Date,
        source: String
    ) {
        self.title = title
        self.sessionDescription = sessionDescription
        self.startTime = startTime
        self.endTime = endTime
        self.date = date
        self.source = source
    }
}
