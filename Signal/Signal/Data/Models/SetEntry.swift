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

    var exercise: WorkoutExercise?

    init(
        setIndex: Int,
        setType: String,
        weightKg: Double? = nil,
        reps: Int? = nil,
        distanceKm: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil
    ) {
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.rpe = rpe
    }
}
