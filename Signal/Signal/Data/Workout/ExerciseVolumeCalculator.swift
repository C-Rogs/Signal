import Foundation
import SwiftData

struct ExerciseLoadPR: Sendable, Equatable {
    let weightKg: Double
    let reps: Int
    let score: Double
}

enum ExerciseVolumeCalculator {
    @MainActor
    static func averageWorkingSetVolume(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        sessionLimit: Int = 8,
        in context: ModelContext
    ) throws -> Double? {
        guard sessionLimit > 0 else { return nil }
        let volumes = try sessionVolumes(
            catalogEntry: catalogEntry,
            exerciseTitle: exerciseTitle,
            sessionLimit: sessionLimit,
            in: context
        )
        guard !volumes.isEmpty else { return nil }
        return volumes.reduce(0, +) / Double(volumes.count)
    }

    @MainActor
    static func bestLoadPR(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        in context: ModelContext
    ) throws -> ExerciseLoadPR? {
        let completedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = try context.fetch(completedDescriptor)

        var best: ExerciseLoadPR?
        for session in sessions {
            guard let exercise = session.exercises.first(where: {
                ExerciseDetailHistoryLoader.matches(
                    exercise: $0,
                    catalogEntry: catalogEntry,
                    exerciseTitle: exerciseTitle
                )
            }) else { continue }

            for set in exercise.sets {
                guard WorkoutSetType(storageValue: set.setType) != .warmup,
                      let weight = set.weightKg,
                      let reps = set.reps,
                      weight > 0,
                      reps >= 1
                else { continue }
                let score = weight * Double(reps)
                if best == nil || score > best!.score {
                    best = ExerciseLoadPR(weightKg: weight, reps: reps, score: score)
                }
            }
        }
        return best
    }

    @MainActor
    private static func sessionVolumes(
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        sessionLimit: Int,
        in context: ModelContext
    ) throws -> [Double] {
        let completedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = try context.fetch(completedDescriptor)

        var volumes: [Double] = []
        for session in sessions {
            guard let exercise = session.exercises.first(where: {
                ExerciseDetailHistoryLoader.matches(
                    exercise: $0,
                    catalogEntry: catalogEntry,
                    exerciseTitle: exerciseTitle
                )
            }) else { continue }

            let volume = workingSetVolume(for: exercise)
            if volume > 0 {
                volumes.append(volume)
            }
            if volumes.count >= sessionLimit { break }
        }
        return volumes
    }

    @MainActor
    private static func workingSetVolume(for exercise: WorkoutExercise) -> Double {
        exercise.sets.reduce(into: 0.0) { total, set in
            guard WorkoutSetType(storageValue: set.setType) != .warmup,
                  let weight = set.weightKg,
                  let reps = set.reps,
                  weight > 0,
                  reps >= 1
            else { return }
            total += weight * Double(reps)
        }
    }
}
