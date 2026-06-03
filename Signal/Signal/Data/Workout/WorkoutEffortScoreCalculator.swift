import Foundation

/// Maps live session RPE into Apple Health `workoutEffortScore` (`appleEffortScore`, 1 through 10).
///
/// - Set RPE: mean of `rpe` on completed non-warmup sets; round to nearest integer; clamp 1...10.
/// - No set RPE: use the 1...10 perceived-effort value from the finish wellness sheet.
/// - HealthKit stores the score as `HKQuantity` in `HKUnit.appleEffortScore()`.
enum WorkoutEffortScoreCalculator {
    static let scale = 1.0 ... 10.0

    static func hasWorkingSetRPE(in session: WorkoutSession) -> Bool {
        !workingSetRPEValues(in: session).isEmpty
    }

    static func meanScore(for session: WorkoutSession) -> Double? {
        let values = workingSetRPEValues(in: session)
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return clampAndRound(mean)
    }

    static func clampAndRound(_ value: Double) -> Double {
        let rounded = value.rounded()
        return min(scale.upperBound, max(scale.lowerBound, rounded))
    }

    private static func workingSetRPEValues(in session: WorkoutSession) -> [Double] {
        var values: [Double] = []
        for exercise in session.exercises {
            for set in exercise.sets where set.isCompleted {
                guard WorkoutSetType(storageValue: set.setType) != .warmup else { continue }
                guard let rpe = set.rpe, rpe.isFinite else { continue }
                values.append(rpe)
            }
        }
        return values
    }
}
