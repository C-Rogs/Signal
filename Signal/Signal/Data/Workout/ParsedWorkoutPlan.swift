import Foundation

struct ParsedWorkoutSet: Sendable, Equatable {
    let setIndex: Int
    let weightKg: Double?
    let reps: Int?
    let rpe: Double?
    let isWarmup: Bool
    let prescriptionNote: String?
    let restDurationSeconds: Int?

    init(
        setIndex: Int,
        weightKg: Double?,
        reps: Int?,
        rpe: Double?,
        isWarmup: Bool,
        prescriptionNote: String?,
        restDurationSeconds: Int? = nil
    ) {
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.prescriptionNote = prescriptionNote
        self.restDurationSeconds = restDurationSeconds
    }
}

struct ParsedExercise: Sendable, Equatable {
    let exerciseTitle: String
    let sets: [ParsedWorkoutSet]
    let restDurationSeconds: Int?

    init(
        exerciseTitle: String,
        sets: [ParsedWorkoutSet],
        restDurationSeconds: Int? = nil
    ) {
        self.exerciseTitle = exerciseTitle
        self.sets = sets
        self.restDurationSeconds = restDurationSeconds
    }
}

struct ParsedWorkoutPlan: Sendable, Equatable {
    let title: String
    let exercises: [ParsedExercise]
    let skippedLines: [String]
}

enum ParsedWorkoutTitle {
    nonisolated static func catalogMatchTitle(from displayTitle: String) -> String {
        let stripped = ExerciseTitleNormalizer.stripParentheticals(displayTitle)
        return stripped.isEmpty ? displayTitle.trimmingCharacters(in: .whitespacesAndNewlines) : stripped
    }
}
