import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var backupID: UUID?
    var title: String
    var sessionDescription: String?
    var startTime: Date
    var endTime: Date?
    var date: Date
    var source: String
    var healthKitWorkoutUUID: String?
    var healthKitEffortSampleUUID: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.session)
    var exercises: [WorkoutExercise] = []

    @Relationship(deleteRule: .cascade, inverse: \WellnessEntry.session)
    var wellnessEntries: [WellnessEntry] = []

    init(
        title: String,
        sessionDescription: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        date: Date,
        source: String,
        healthKitWorkoutUUID: String? = nil,
        healthKitEffortSampleUUID: String? = nil
    ) {
        self.title = title
        self.sessionDescription = sessionDescription
        self.startTime = startTime
        self.endTime = endTime
        self.date = date
        self.source = source
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.healthKitEffortSampleUUID = healthKitEffortSampleUUID
    }
}
