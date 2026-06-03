import Foundation
import SwiftData

@Model
final class TrainingGoal {
    var goalKey: String
    var primaryGoalRaw: String
    var weeklyTrainingDays: Int
    var targetRIR: Int
    var updatedAt: Date
    var notes: String?

    var primaryGoal: GoalType {
        get { GoalType(rawValue: primaryGoalRaw) ?? .generalFitness }
        set { primaryGoalRaw = newValue.rawValue }
    }

    init(
        goalKey: String = ProfileGoalRepository.primaryGoalKey,
        primaryGoal: GoalType = .generalFitness,
        weeklyTrainingDays: Int = 4,
        targetRIR: Int? = nil,
        updatedAt: Date = .now,
        notes: String? = nil
    ) {
        self.goalKey = goalKey
        self.primaryGoalRaw = primaryGoal.rawValue
        self.weeklyTrainingDays = min(7, max(1, weeklyTrainingDays))
        self.targetRIR = targetRIR ?? primaryGoal.defaultRIR
        self.updatedAt = updatedAt
        self.notes = notes
    }
}
