import Foundation
import HealthKit

enum TrainWorkoutHealthKitConfiguration {
    static func make(for session: WorkoutSession) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: session)
        configuration.locationType = .indoor
        return configuration
    }

    static func activityType(for session: WorkoutSession) -> HKWorkoutActivityType {
        let titles = session.exercises.map { $0.exerciseTitle.lowercased() }
        let functionalKeywords = ["clean", "snatch", "jerk", "burpee", "kettlebell", "crossfit", "functional"]
        if titles.contains(where: { title in functionalKeywords.contains(where: title.contains) }) {
            return .functionalStrengthTraining
        }
        return .traditionalStrengthTraining
    }

    static func make(configuration activityType: HKWorkoutActivityType) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor
        return configuration
    }

    static func make(activityTypeRawValue: UInt?) -> HKWorkoutConfiguration {
        let activity = activityTypeRawValue.flatMap { HKWorkoutActivityType(rawValue: $0) }
            ?? .traditionalStrengthTraining
        return make(configuration: activity)
    }
}
