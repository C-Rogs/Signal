import Foundation

enum FractionalVolume {
    static let primaryMultiplier = 1.0
    static let secondaryMultiplier = 0.5

    static func fractionalVolume(for set: SetEntry, exercise: WorkoutExercise) -> [Muscle: Double] {
        guard countsTowardVolume(set) else { return [:] }
        guard let catalog = exercise.catalogEntry else { return [:] }
        return fractionalVolume(primary: catalog.primaryMuscles, secondary: catalog.secondaryMuscles)
    }

    static func fractionalVolume(primary: [Muscle], secondary: [Muscle]) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for muscle in primary {
            totals[muscle, default: 0] += primaryMultiplier
        }
        for muscle in secondary where !primary.contains(muscle) {
            totals[muscle, default: 0] += secondaryMultiplier
        }
        return totals
    }

    static func countsTowardVolume(_ set: SetEntry) -> Bool {
        set.setType.lowercased() != "warmup"
    }
}
