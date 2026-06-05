import Foundation
import SwiftData
@testable import Signal

enum CoachUATFixtureSeeder {
    @MainActor
    static func seed(in container: ModelContainer) async throws {
        let context = ModelContext(container)
        let calendar = SchedulingCalendar.make()
        let today = calendar.startOfDay(for: Date())

        for dayOffset in -13...0 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            context.insert(
                DailyMetric(
                    date: day,
                    hrvSDNN_ms: 48 + Double(dayOffset % 5),
                    restingHR: dayOffset == 0 ? 62 : 58,
                    sleepHours: dayOffset == 0 ? 6.2 : 7.4,
                    source: "coach_uat"
                )
            )
        }

        let squatDay = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        let session = WorkoutSession(
            title: "Legs",
            startTime: squatDay,
            date: squatDay,
            source: HevyCSVImporter.importSource
        )
        context.insert(session)

        let exercise = WorkoutExercise(
            exerciseTitle: "Squat (Barbell)",
            order: 0
        )
        exercise.session = session
        context.insert(exercise)

        let set = SetEntry(
            setIndex: 0,
            setType: "normal",
            weightKg: 100,
            reps: 5,
            rpe: 8,
            isCompleted: true
        )
        set.exercise = exercise
        context.insert(set)

        try context.save()
        EmbeddingBackend.useDeterministicTestEmbedding = true
        await DerivedMetricsService.shared.invalidateCache()
    }
}
