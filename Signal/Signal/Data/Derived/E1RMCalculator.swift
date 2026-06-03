import Foundation

struct E1RMCalculator: Sendable {
    func epley(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)
    }

    func brzycki(weight: Double, reps: Int) -> Double {
        guard reps < 37 else { return 0 }
        return weight * 36.0 / (37.0 - Double(reps))
    }

    func best(weight: Double, reps: Int) -> Double? {
        guard reps >= 1, reps <= 30, weight > 0 else { return nil }
        let e = epley(weight: weight, reps: reps)
        let b = brzycki(weight: weight, reps: reps)
        return (e + b) / 2.0
    }
}

struct ExerciseE1RMBest: Sendable, Equatable {
    let e1RMKg: Double
    let bestSetWeightKg: Double
    let bestSetReps: Int
}

enum ExerciseE1RMAggregator {
    private static let calculator = E1RMCalculator()

    static func bestWorkingSetE1RM(for exercise: WorkoutExercise) -> ExerciseE1RMBest? {
        var best: ExerciseE1RMBest?
        for set in exercise.sets {
            guard !isWarmup(set) else { continue }
            guard let weight = set.weightKg, let reps = set.reps else { continue }
            guard let estimate = calculator.best(weight: weight, reps: reps) else { continue }
            if best == nil || estimate > best!.e1RMKg {
                best = ExerciseE1RMBest(
                    e1RMKg: estimate,
                    bestSetWeightKg: weight,
                    bestSetReps: reps
                )
            }
        }
        return best
    }

    static func exerciseID(for exercise: WorkoutExercise) -> String {
        if let name = exercise.catalogEntry?.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return exercise.exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isWarmup(_ set: SetEntry) -> Bool {
        WorkoutSetType(storageValue: set.setType) == .warmup
    }
}
