import Foundation

enum ExerciseCompletionStatus: Sendable {
    case complete
    case inProgress
    case notStarted

    static func status(for exercise: WorkoutExercise) -> ExerciseCompletionStatus {
        let sets = exercise.sets
        guard !sets.isEmpty else { return .notStarted }
        let completed = sets.filter(\.isCompleted).count
        if completed == sets.count { return .complete }
        if completed > 0 || sets.contains(where: \.hasBeenEdited) { return .inProgress }
        return .notStarted
    }

    var label: String {
        switch self {
        case .complete: "Complete"
        case .inProgress: "In progress"
        case .notStarted: "Not started"
        }
    }

    var systemImage: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .notStarted: "circle"
        }
    }
}

enum WorkoutSessionCompletionSummary {
    static func incompleteExercises(in session: WorkoutSession) -> [WorkoutExercise] {
        session.exercises
            .sorted { $0.order < $1.order }
            .filter { ExerciseCompletionStatus.status(for: $0) != .complete }
    }

    static func completedSetCount(in exercise: WorkoutExercise) -> (done: Int, total: Int) {
        let total = exercise.sets.count
        let done = exercise.sets.filter(\.isCompleted).count
        return (done, total)
    }
}
