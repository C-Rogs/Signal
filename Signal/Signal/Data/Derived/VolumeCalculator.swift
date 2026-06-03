import Foundation

struct VolumeSetContribution: Sendable, Equatable {
    let set: SetEntry
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]

    var isWarmup: Bool {
        WorkoutSetType(storageValue: set.setType) == .warmup
    }

    init(set: SetEntry, primaryMuscles: [Muscle], secondaryMuscles: [Muscle]) {
        self.set = set
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
    }

    init(set: SetEntry, catalog: ExerciseCatalog?) {
        self.set = set
        self.primaryMuscles = catalog?.primaryMuscles ?? []
        self.secondaryMuscles = catalog?.secondaryMuscles ?? []
    }
}

enum VolumeCalculator {
    static let primaryMultiplier = 1.0
    static let secondaryMultiplier = 0.5

    static func fractionalVolume(for contributions: [VolumeSetContribution]) -> [MuscleGroup: Double] {
        var totals: [MuscleGroup: Double] = [:]
        for contribution in contributions {
            guard !contribution.isWarmup else { continue }
            let muscleTotals = FractionalVolume.fractionalVolume(
                primary: contribution.primaryMuscles,
                secondary: contribution.secondaryMuscles
            )
            for (muscle, amount) in muscleTotals {
                for group in MuscleGroup.groups(for: muscle) {
                    totals[group, default: 0] += amount
                }
            }
        }
        return totals
    }

    static func fractionalVolume(for sets: [SetEntry]) -> [MuscleGroup: Double] {
        fractionalVolume(
            for: sets.map { VolumeSetContribution(set: $0, primaryMuscles: [], secondaryMuscles: []) }
        )
    }

    static func contributions(from exercise: WorkoutExercise) -> [VolumeSetContribution] {
        exercise.sets.map { VolumeSetContribution(set: $0, catalog: exercise.catalogEntry) }
    }

    static func integerSetCount(from fractionalSets: Double) -> String {
        if fractionalSets == fractionalSets.rounded() {
            return String(Int(fractionalSets.rounded()))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), fractionalSets)
    }
}
