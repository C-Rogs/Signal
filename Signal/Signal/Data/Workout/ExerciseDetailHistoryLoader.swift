import Foundation
import SwiftData

struct ExerciseHistorySession: Identifiable, Sendable, Equatable {
    let sessionID: PersistentIdentifier
    let sessionTitle: String
    let date: Date
    let setSummaries: [String]

    var id: PersistentIdentifier { sessionID }
}

enum ExerciseDetailHistoryLoader {
    @MainActor
    static func loadRecentSessions(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        limit: Int,
        formatter: DisplayUnitFormatter,
        in context: ModelContext
    ) throws -> [ExerciseHistorySession] {
        guard limit > 0 else { return [] }

        let completedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let completedSessions = try context.fetch(completedDescriptor)

        var results: [ExerciseHistorySession] = []
        for session in completedSessions {
            guard let match = matchingExercise(
                in: session,
                catalogEntry: catalogEntry,
                exerciseTitle: exerciseTitle
            ) else { continue }

            let summaries = formatSetSummaries(for: match, formatter: formatter)
            results.append(
                ExerciseHistorySession(
                    sessionID: session.persistentModelID,
                    sessionTitle: session.title,
                    date: session.endTime ?? session.startTime,
                    setSummaries: summaries
                )
            )
            if results.count >= limit { break }
        }
        return results
    }

    @MainActor
    static func matches(
        exercise: WorkoutExercise,
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String
    ) -> Bool {
        if let catalogEntry {
            if let entry = exercise.catalogEntry {
                return entry.persistentModelID == catalogEntry.persistentModelID
            }
            let exerciseNorm = ExerciseTitleNormalizer.normalize(exercise.exerciseTitle)
            let catalogNorm = ExerciseTitleNormalizer.normalize(catalogEntry.canonicalName)
            return exerciseNorm == catalogNorm
        }
        let lhs = ExerciseTitleNormalizer.normalize(exercise.exerciseTitle)
        let rhs = ExerciseTitleNormalizer.normalize(exerciseTitle)
        return lhs == rhs
    }

    @MainActor
    private static func matchingExercise(
        in session: WorkoutSession,
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String
    ) -> WorkoutExercise? {
        session.exercises.first {
            matches(exercise: $0, catalogEntry: catalogEntry, exerciseTitle: exerciseTitle)
        }
    }

    @MainActor
    private static func formatSetSummaries(
        for exercise: WorkoutExercise,
        formatter: DisplayUnitFormatter
    ) -> [String] {
        let mode = ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry)
        return exercise.sets
            .sorted { $0.setIndex < $1.setIndex }
            .map { set in
                let setType = WorkoutSetType(storageValue: set.setType) ?? .normal
                switch mode {
                case .strength:
                    return WorkoutHistoryDetailFormatting.strengthLoadLine(
                        weightLabel: formatter.formatMassKg(set.weightKg),
                        reps: set.reps,
                        rpe: set.rpe,
                        setType: setType
                    )
                case .cardio:
                    return WorkoutHistoryDetailFormatting.cardioLoadLine(
                        distanceLabel: formatter.formatDistanceKm(set.distanceKm),
                        durationLabel: formatDuration(set.durationSeconds),
                        rpe: set.rpe,
                        setType: setType
                    )
                }
            }
    }

    private static func formatDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
