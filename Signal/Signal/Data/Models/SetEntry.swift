import Foundation
import SwiftData

@Model
final class SetEntry {
    var setIndex: Int
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var distanceKm: Double?
    var durationSeconds: Int?
    var rpe: Double?
    var isCompleted: Bool = false
    var hasBeenEdited: Bool = false
    var startedAt: Date?
    var completedAt: Date?

    var exercise: WorkoutExercise?

    init(
        setIndex: Int,
        setType: String,
        weightKg: Double? = nil,
        reps: Int? = nil,
        distanceKm: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil,
        isCompleted: Bool = false,
        hasBeenEdited: Bool = false,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.hasBeenEdited = hasBeenEdited
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
