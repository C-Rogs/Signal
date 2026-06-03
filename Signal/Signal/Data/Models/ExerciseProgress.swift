import Foundation
import SwiftData

@Model
final class ExerciseProgress {
    var exerciseID: String
    var sessionDate: Date
    var sessionID: String
    var e1RM_kg: Double
    var bestSetWeight_kg: Double
    var bestSetReps: Int

    init(
        exerciseID: String,
        sessionDate: Date,
        sessionID: String,
        e1RM_kg: Double,
        bestSetWeight_kg: Double,
        bestSetReps: Int
    ) {
        self.exerciseID = exerciseID
        self.sessionDate = sessionDate
        self.sessionID = sessionID
        self.e1RM_kg = e1RM_kg
        self.bestSetWeight_kg = bestSetWeight_kg
        self.bestSetReps = bestSetReps
    }
}
