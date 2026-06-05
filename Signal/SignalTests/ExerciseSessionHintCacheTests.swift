import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseSessionHintCacheTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var formatter: DisplayUnitFormatter!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
        formatter = DisplayUnitFormatter(preferences: UnitPreferences())
        LastSessionAutofill.resetFetchCountForTesting()
    }

    override func tearDownWithError() throws {
        LastSessionAutofill.resetFetchCountForTesting()
    }

    func testWarmFetchesOncePerExercise() throws {
        insertCompletedSession(exerciseTitle: "Bench Press", weight: 60, reps: 8)
        insertCompletedSession(exerciseTitle: "Squat", weight: 100, reps: 5)

        let live = WorkoutSession(
            title: "Live",
            startTime: .now,
            endTime: nil,
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(live)

        let bench = WorkoutExercise(exerciseTitle: "Bench Press", order: 0)
        bench.session = live
        live.exercises.append(bench)

        let squat = WorkoutExercise(exerciseTitle: "Squat", order: 1)
        squat.session = live
        live.exercises.append(squat)

        let curl = WorkoutExercise(exerciseTitle: "Curl", order: 2)
        curl.session = live
        live.exercises.append(curl)

        try context.save()
        LastSessionAutofill.resetFetchCountForTesting()

        let cache = ExerciseSessionHintCache()
        cache.warm(exercises: [bench, squat, curl], formatter: formatter, in: context)
        XCTAssertEqual(LastSessionAutofill.findLastExerciseFetchCountForTesting, 3)

        LastSessionAutofill.resetFetchCountForTesting()
        for _ in 0..<60 {
            _ = cache.lastHint(for: bench)
            _ = cache.previousHint(for: bench, setIndex: 0)
            _ = cache.lastHint(for: squat)
            _ = cache.previousHint(for: squat, setIndex: 0)
            _ = cache.lastHint(for: curl)
        }
        XCTAssertEqual(LastSessionAutofill.findLastExerciseFetchCountForTesting, 0)
    }

    func testRefreshUpdatesHintsAfterNewCompletedSession() throws {
        insertCompletedSession(exerciseTitle: "Deadlift", weight: 120, reps: 3)

        let live = WorkoutSession(
            title: "Live",
            startTime: .now,
            endTime: nil,
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(live)
        let exercise = WorkoutExercise(exerciseTitle: "Deadlift", order: 0)
        exercise.session = live
        live.exercises.append(exercise)
        try context.save()

        let cache = ExerciseSessionHintCache()
        cache.warm(exercises: [exercise], formatter: formatter, in: context)
        let firstHint = cache.lastHint(for: exercise)

        insertCompletedSession(
            exerciseTitle: "Deadlift",
            weight: 130,
            reps: 2,
            startOffset: -3_600
        )
        cache.refresh(exercise: exercise, formatter: formatter, in: context)
        let secondHint = cache.lastHint(for: exercise)

        XCTAssertNotEqual(firstHint, secondHint)
        XCTAssertTrue(secondHint?.contains("130") == true)
    }

    func testInvalidateClearsEntries() throws {
        insertCompletedSession(exerciseTitle: "Row", weight: 50, reps: 10)

        let live = WorkoutSession(
            title: "Live",
            startTime: .now,
            endTime: nil,
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(live)
        let exercise = WorkoutExercise(exerciseTitle: "Row", order: 0)
        exercise.session = live
        live.exercises.append(exercise)
        try context.save()

        let cache = ExerciseSessionHintCache()
        cache.warm(exercises: [exercise], formatter: formatter, in: context)
        XCTAssertNotNil(cache.lastHint(for: exercise))

        cache.invalidate()
        XCTAssertNil(cache.lastHint(for: exercise))
    }

    private func insertCompletedSession(
        exerciseTitle: String,
        weight: Double,
        reps: Int,
        startOffset: TimeInterval = -86_400
    ) {
        let prior = WorkoutSession(
            title: "Prior",
            startTime: .now.addingTimeInterval(startOffset),
            endTime: .now.addingTimeInterval(startOffset + 3_600),
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(prior)
        let exercise = WorkoutExercise(exerciseTitle: exerciseTitle, order: 0)
        exercise.session = prior
        prior.exercises.append(exercise)
        let set = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: weight,
            reps: reps,
            isCompleted: true
        )
        set.exercise = exercise
        exercise.sets.append(set)
        try? context.save()
    }
}
