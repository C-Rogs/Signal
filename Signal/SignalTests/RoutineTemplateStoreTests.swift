import SwiftData
import XCTest
@testable import Signal

@MainActor
final class RoutineTemplateStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var templateStore: RoutineTemplateStore!
    private var workoutStore: LiveWorkoutStore!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
        templateStore = RoutineTemplateStore(context: context)
        workoutStore = LiveWorkoutStore(context: context)
    }

    override func tearDownWithError() throws {
        templateStore = nil
        workoutStore = nil
        context = nil
        container = nil
    }

    func testCreateRoutineFromParsedPlan() throws {
        let request = ParsedPlanStartRequest(
            title: "Push Day",
            exercises: [
                ParsedPlanStartRequest.ParsedPlanExercise(
                    exerciseTitle: "Bench Press",
                    catalogEntry: nil,
                    sets: [
                        ParsedWorkoutSet(
                            setIndex: 0,
                            weightKg: 80,
                            reps: 8,
                            rpe: 8,
                            isWarmup: false,
                            prescriptionNote: nil,
                            restDurationSeconds: 90
                        ),
                        ParsedWorkoutSet(
                            setIndex: 1,
                            weightKg: 40,
                            reps: 12,
                            rpe: nil,
                            isWarmup: true,
                            prescriptionNote: nil
                        ),
                    ],
                    restDurationSeconds: 90
                ),
            ]
        )

        let routine = try templateStore.createRoutine(name: "Push Day", from: request)
        XCTAssertEqual(routine.name, "Push Day")
        XCTAssertEqual(routine.exercises.count, 1)

        let slot = try XCTUnwrap(routine.exercises.first)
        XCTAssertEqual(slot.restDurationSeconds, 90)
        XCTAssertEqual(slot.sortedPresetSets.count, 2)

        let workingSet = slot.sortedPresetSets[0]
        XCTAssertEqual(workingSet.weightKg, 80)
        XCTAssertEqual(workingSet.reps, 8)
        XCTAssertEqual(workingSet.rpe, 8)
        XCTAssertEqual(workingSet.restDurationSeconds, 90)
        XCTAssertEqual(WorkoutSetType(storageValue: workingSet.setType), .normal)

        let warmupSet = slot.sortedPresetSets[1]
        XCTAssertEqual(WorkoutSetType(storageValue: warmupSet.setType), .warmup)
        XCTAssertEqual(warmupSet.weightKg, 40)

        XCTAssertEqual(templateStore.totalPresetSetCount(for: routine), 2)
    }

    func testStartRoutineWithPresetsIgnoresLastSession() throws {
        let priorSession = WorkoutSession(
            title: "Prior",
            startTime: .now,
            endTime: .now,
            date: Calendar.current.startOfDay(for: .now),
            source: WorkoutSessionSource.live
        )
        context.insert(priorSession)
        let priorExercise = WorkoutExercise(exerciseTitle: "Bench Press", order: 0)
        priorExercise.session = priorSession
        priorSession.exercises.append(priorExercise)
        let priorSet = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 999,
            reps: 99
        )
        priorSet.exercise = priorExercise
        priorExercise.sets.append(priorSet)
        try context.save()

        let request = ParsedPlanStartRequest(
            title: "Push Day",
            exercises: [
                ParsedPlanStartRequest.ParsedPlanExercise(
                    exerciseTitle: "Bench Press",
                    catalogEntry: nil,
                    sets: [
                        ParsedWorkoutSet(
                            setIndex: 0,
                            weightKg: 80,
                            reps: 8,
                            rpe: nil,
                            isWarmup: false,
                            prescriptionNote: nil
                        ),
                    ]
                ),
            ]
        )
        let routine = try templateStore.createRoutine(name: "Push Day", from: request)

        let session = try workoutStore.start(from: routine)
        let exercise = try XCTUnwrap(session.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        XCTAssertEqual(set.weightKg, 80)
        XCTAssertEqual(set.reps, 8)
        XCTAssertNotEqual(set.weightKg, 999)
    }

    func testStartRoutineWithoutPresetsUsesAutofill() throws {
        let priorSession = WorkoutSession(
            title: "Prior",
            startTime: .now,
            endTime: .now,
            date: Calendar.current.startOfDay(for: .now),
            source: WorkoutSessionSource.live
        )
        context.insert(priorSession)
        let priorExercise = WorkoutExercise(exerciseTitle: "Squat", order: 0)
        priorExercise.session = priorSession
        priorSession.exercises.append(priorExercise)
        let priorSet = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 100,
            reps: 5
        )
        priorSet.exercise = priorExercise
        priorExercise.sets.append(priorSet)
        try context.save()

        let routine = Routine(name: "Leg Day")
        context.insert(routine)
        let slot = RoutineExercise(
            order: 0,
            exerciseTitleFallback: "Squat"
        )
        slot.routine = routine
        routine.exercises.append(slot)
        try context.save()

        let session = try workoutStore.start(from: routine)
        let exercise = try XCTUnwrap(session.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        XCTAssertEqual(set.weightKg, 100)
        XCTAssertEqual(set.reps, 5)
    }

    func testStartRoutinePreservesRest() throws {
        let request = ParsedPlanStartRequest(
            title: "Rest Routine",
            exercises: [
                ParsedPlanStartRequest.ParsedPlanExercise(
                    exerciseTitle: "Squat",
                    catalogEntry: nil,
                    sets: [
                        ParsedWorkoutSet(
                            setIndex: 0,
                            weightKg: 100,
                            reps: 5,
                            rpe: nil,
                            isWarmup: false,
                            prescriptionNote: nil,
                            restDurationSeconds: 60
                        ),
                    ],
                    restDurationSeconds: 120
                ),
            ]
        )
        let routine = try templateStore.createRoutine(name: "Rest Routine", from: request)

        let session = try workoutStore.start(from: routine)
        let exercise = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(exercise.restDurationSeconds, 120)
        XCTAssertTrue(exercise.autoStartRestOnSetComplete)

        let set = try XCTUnwrap(exercise.sets.first)
        XCTAssertEqual(set.restDurationSeconds, 60)

        try workoutStore.toggleSetComplete(set, exercise: exercise, completed: true)
        let endsAt = try XCTUnwrap(exercise.restTimerEndsAt)
        let expected = Date.now.addingTimeInterval(60)
        XCTAssertEqual(endsAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 2)
    }
}
