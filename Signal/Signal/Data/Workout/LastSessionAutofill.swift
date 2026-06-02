import Foundation
import SwiftData

struct SetAutofillTemplate: Sendable, Equatable {
    let setIndex: Int
    let setType: String
    let weightKg: Double?
    let reps: Int?
    let distanceKm: Double?
    let durationSeconds: Int?
    let rpe: Double?
}

@MainActor
enum LastSessionAutofill {
    static func templates(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        mode: ExerciseLoggingMode,
        in context: ModelContext
    ) throws -> [SetAutofillTemplate] {
        guard let exercise = try findLastExercise(
            catalogEntry: catalogEntry,
            exerciseTitle: exerciseTitle,
            in: context
        ) else {
            return [defaultTemplate(setIndex: 0, mode: mode)]
        }

        let sortedSets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        guard !sortedSets.isEmpty else {
            return [defaultTemplate(setIndex: 0, mode: mode)]
        }

        return sortedSets.enumerated().map { offset, set in
            SetAutofillTemplate(
                setIndex: offset,
                setType: set.setType,
                weightKg: mode == .strength ? set.weightKg : nil,
                reps: mode == .strength ? set.reps : nil,
                distanceKm: mode == .cardio ? set.distanceKm : nil,
                durationSeconds: mode == .cardio ? set.durationSeconds : nil,
                rpe: set.rpe
            )
        }
    }

    static func lastSessionHint(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        mode: ExerciseLoggingMode,
        in context: ModelContext,
        formatter: DisplayUnitFormatter
    ) throws -> String? {
        guard let exercise = try findLastExercise(
            catalogEntry: catalogEntry,
            exerciseTitle: exerciseTitle,
            in: context
        ) else { return nil }

        let workingSets = exercise.sets
            .sorted { $0.setIndex < $1.setIndex }
            .filter { !isWarmup($0) }
        guard let last = workingSets.last ?? exercise.sets.sorted(by: { $0.setIndex < $1.setIndex }).last else {
            return nil
        }

        switch mode {
        case .strength:
            let weightText = formatter.formatMassKg(last.weightKg)
            let reps = last.reps.map(String.init) ?? "—"
            return "Last: \(weightText) × \(reps)"
        case .cardio:
            let distance = formatter.formatDistanceKm(last.distanceKm)
            let duration = formatDuration(last.durationSeconds)
            return "Last: \(distance) / \(duration)"
        }
    }

    private static func findLastExercise(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        in context: ModelContext
    ) throws -> WorkoutExercise? {
        let completed = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.endTime != nil },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
        )

        let normalizedTitle = ExerciseTitleNormalizer.normalize(exerciseTitle)

        for session in completed {
            let ordered = session.exercises.sorted { $0.order < $1.order }
            for exercise in ordered {
                if let catalogEntry, exercise.catalogEntry?.canonicalName == catalogEntry.canonicalName {
                    return exercise
                }
                if ExerciseTitleNormalizer.normalize(exercise.exerciseTitle) == normalizedTitle {
                    return exercise
                }
            }
        }
        return nil
    }

    private static func defaultTemplate(setIndex: Int, mode: ExerciseLoggingMode) -> SetAutofillTemplate {
        SetAutofillTemplate(
            setIndex: setIndex,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: nil,
            reps: mode == .strength ? nil : nil,
            distanceKm: mode == .cardio ? nil : nil,
            durationSeconds: mode == .cardio ? nil : nil,
            rpe: nil
        )
    }

    private static func isWarmup(_ set: SetEntry) -> Bool {
        WorkoutSetType(storageValue: set.setType) == .warmup
    }

    private static func formatDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
