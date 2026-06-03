import Foundation
import SwiftData
import os

enum ExerciseProgressStore {
    @MainActor
    static func upsert(
        exerciseID: String,
        session: WorkoutSession,
        best: ExerciseE1RMBest,
        in context: ModelContext
    ) throws {
        let sessionID = sessionIDString(for: session)
        let sessionDate = Calendar.current.startOfDay(for: session.date)

        let sessionDescriptor = FetchDescriptor<ExerciseProgress>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        let existing = try context.fetch(sessionDescriptor).first { $0.exerciseID == exerciseID }

        if let existing {
            existing.sessionDate = sessionDate
            existing.e1RM_kg = best.e1RMKg
            existing.bestSetWeight_kg = best.bestSetWeightKg
            existing.bestSetReps = best.bestSetReps
        } else {
            context.insert(
                ExerciseProgress(
                    exerciseID: exerciseID,
                    sessionDate: sessionDate,
                    sessionID: sessionID,
                    e1RM_kg: best.e1RMKg,
                    bestSetWeight_kg: best.bestSetWeightKg,
                    bestSetReps: best.bestSetReps
                )
            )
        }
        try context.save()
    }

    @MainActor
    static func recordSession(_ session: WorkoutSession, in context: ModelContext) throws -> Int {
        let sessionID = session.persistentModelID
        guard let resolved = context.model(for: sessionID) as? WorkoutSession else {
            Log.workout.error("exercise progress skipped; session not found in store")
            return 0
        }

        var written = 0
        for exercise in resolved.exercises {
            guard let best = ExerciseE1RMAggregator.bestWorkingSetE1RM(for: exercise) else {
                logSkippedExercise(exercise)
                continue
            }
            let exerciseID = ExerciseE1RMAggregator.exerciseID(for: exercise)
            guard !exerciseID.isEmpty else { continue }
            try upsert(exerciseID: exerciseID, session: resolved, best: best, in: context)
            written += 1
        }
        if written > 0 {
            Log.workout.info(
                "exercise progress upserted session=\(String(describing: sessionID), privacy: .public) rows=\(written, privacy: .public)"
            )
        } else {
            Log.workout.info(
                "exercise progress wrote zero rows session=\(String(describing: sessionID), privacy: .public) exercises=\(resolved.exercises.count, privacy: .public)"
            )
        }
        return written
    }

    @MainActor
    static func backfillMissingRecentSessions(in context: ModelContext, limit: Int = 40) throws {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let sessions = try context.fetch(descriptor)
        var backfilled = 0
        for session in sessions {
            let sid = sessionIDString(for: session)
            var progressDescriptor = FetchDescriptor<ExerciseProgress>(
                predicate: #Predicate { $0.sessionID == sid }
            )
            progressDescriptor.fetchLimit = 1
            guard try context.fetch(progressDescriptor).isEmpty else { continue }
            backfilled += try recordSession(session, in: context)
        }
        if backfilled > 0 {
            Log.workout.info("exercise progress backfilled rows=\(backfilled, privacy: .public)")
        }
    }

    @MainActor
    static func recordFinishedSession(_ session: WorkoutSession, in context: ModelContext) {
        guard session.endTime != nil else { return }
        do {
            _ = try recordSession(session, in: context)
            Task { await DerivedMetricsService.shared.invalidateCache() }
        } catch {
            Log.workout.error(
                "exercise progress record failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @MainActor
    private static func logSkippedExercise(_ exercise: WorkoutExercise) {
        let workingSets = exercise.sets.filter { WorkoutSetType(storageValue: $0.setType) != .warmup }
        let withLoad = workingSets.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) >= 1 }
        Log.workout.info(
            "exercise progress skipped exercise=\(exercise.exerciseTitle, privacy: .public) workingSets=\(workingSets.count, privacy: .public) withLoad=\(withLoad.count, privacy: .public)"
        )
    }

    @MainActor
    static func fetchHistory(
        exerciseID: String,
        in context: ModelContext
    ) throws -> [ExerciseProgress] {
        let descriptor = FetchDescriptor<ExerciseProgress>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [
                SortDescriptor(\.sessionDate, order: .forward),
                SortDescriptor(\.e1RM_kg, order: .forward),
            ]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    static func fetchRecentDistinctExercises(
        limit: Int,
        in context: ModelContext
    ) throws -> [ExerciseProgress] {
        let descriptor = FetchDescriptor<ExerciseProgress>(
            sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        var seen: Set<String> = []
        var result: [ExerciseProgress] = []
        for row in rows {
            guard seen.insert(row.exerciseID).inserted else { continue }
            result.append(row)
            if result.count >= limit { break }
        }
        return result
    }

    private static func sessionIDString(for session: WorkoutSession) -> String {
        String(describing: session.persistentModelID)
    }
}
