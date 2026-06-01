import Foundation
import SwiftData
import os

enum WorkoutStore {
    private static let lossyMigrationKey = "signal.hevyStructuredMigrationComplete"

    @MainActor
    static func wipeLossyHevyDataIfNeeded(source: String, in context: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: lossyMigrationKey) else { return }
        try deleteAll(source: source, in: context)
        UserDefaults.standard.set(true, forKey: lossyMigrationKey)
        Log.import.info("wiped prior Hevy workout rows before structured import")
    }

    @MainActor
    static func deleteAll(source: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.source == source }
        )
        let sessions = try context.fetch(descriptor)
        for session in sessions {
            context.delete(session)
        }
        if !sessions.isEmpty {
            try context.save()
        }
    }

    @MainActor
    @discardableResult
    static func upsert(
        parsedSessions: [HevyParsedSession],
        source: String,
        in context: ModelContext
    ) throws -> (sessionCount: Int, exerciseCount: Int, setCount: Int) {
        var exerciseCount = 0
        var setCount = 0

        for parsed in parsedSessions {
            let existing = try fetchSession(
                title: parsed.title,
                startTime: parsed.startTime,
                source: source,
                in: context
            )
            let session = existing ?? WorkoutSession(
                title: parsed.title,
                sessionDescription: parsed.sessionDescription,
                startTime: parsed.startTime,
                endTime: parsed.endTime,
                date: parsed.dayStart,
                source: source
            )

            if existing == nil {
                context.insert(session)
            } else {
                session.sessionDescription = parsed.sessionDescription
                session.endTime = parsed.endTime
                session.date = parsed.dayStart
                for exercise in session.exercises {
                    context.delete(exercise)
                }
                session.exercises = []
            }

            for parsedExercise in parsed.exercises {
                let exercise = WorkoutExercise(
                    exerciseTitle: parsedExercise.exerciseTitle,
                    notes: parsedExercise.notes,
                    supersetId: parsedExercise.supersetId,
                    order: parsedExercise.order
                )
                exercise.session = session
                session.exercises.append(exercise)

                for parsedSet in parsedExercise.sets {
                    let entry = SetEntry(
                        setIndex: parsedSet.setIndex,
                        setType: parsedSet.setType,
                        weightKg: parsedSet.weightKg,
                        reps: parsedSet.reps,
                        distanceKm: parsedSet.distanceKm,
                        durationSeconds: parsedSet.durationSeconds,
                        rpe: parsedSet.rpe
                    )
                    entry.exercise = exercise
                    exercise.sets.append(entry)
                    setCount += 1
                }
                exerciseCount += 1
            }
        }

        try context.save()
        return (sessionCount: parsedSessions.count, exerciseCount: exerciseCount, setCount: setCount)
    }

    @MainActor
    static func fetchSessions(
        for dayStart: Date,
        source: String,
        in context: ModelContext
    ) throws -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date == dayStart && $0.source == source },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    static func counts(source: String, in context: ModelContext) throws -> (sessionCount: Int, exerciseCount: Int, setCount: Int) {
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.source == source })
        )
        var exercises = 0
        var sets = 0
        for session in sessions {
            exercises += session.exercises.count
            for exercise in session.exercises {
                sets += exercise.sets.count
            }
        }
        return (sessionCount: sessions.count, exerciseCount: exercises, setCount: sets)
    }

    @MainActor
    private static func fetchSession(
        title: String,
        startTime: Date,
        source: String,
        in context: ModelContext
    ) throws -> WorkoutSession? {
        let sessionTitle = title
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.title == sessionTitle && $0.startTime == startTime && $0.source == source
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
