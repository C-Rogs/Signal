import SwiftData
import XCTest
@testable import Signal

@MainActor
final class LiveWorkoutStoreSwapTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: LiveWorkoutStore!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
        store = LiveWorkoutStore(context: context)
    }

    func testSwapRebuildsUncompletedSets() throws {
        let sourceCatalog = ExerciseCatalog(
            canonicalName: "Barbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        let substituteCatalog = ExerciseCatalog(
            canonicalName: "Dumbbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .dumbbell
        )
        context.insert(sourceCatalog)
        context.insert(substituteCatalog)

        let prior = WorkoutSession(
            title: "Prior",
            startTime: .now.addingTimeInterval(-86_400),
            endTime: .now.addingTimeInterval(-85_000),
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(prior)
        let priorExercise = WorkoutExercise(
            exerciseTitle: substituteCatalog.canonicalName,
            order: 0,
            catalogEntry: substituteCatalog
        )
        priorExercise.session = prior
        prior.exercises.append(priorExercise)
        let priorSet = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 36,
            reps: 10
        )
        priorSet.exercise = priorExercise
        priorExercise.sets.append(priorSet)
        try context.save()

        let session = try store.startEmpty()
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: sourceCatalog,
            exerciseTitle: sourceCatalog.canonicalName
        )
        let completed = exercise.sets[0]
        try store.toggleSetComplete(completed, exercise: exercise, completed: true)

        let plan = SwapSetPlan(
            sets: [
                SwapSetTemplate(
                    setIndex: 0,
                    setType: WorkoutSetType.normal.storageValue,
                    weightKg: 38,
                    reps: 10,
                    distanceKm: nil,
                    durationSeconds: nil
                ),
            ],
            progressionIntent: .hold,
            substituteHasHistory: true,
            noHistoryNote: nil
        )

        try store.swapExercise(
            exercise,
            catalogEntry: substituteCatalog,
            exerciseTitle: substituteCatalog.canonicalName,
            plan: plan
        )

        XCTAssertEqual(exercise.catalogEntry?.canonicalName, "Dumbbell Bench Press")
        XCTAssertEqual(exercise.sets.count, 2)
        XCTAssertTrue(exercise.sets.contains { $0.isCompleted })
        let uncompleted = exercise.sets.filter { !$0.isCompleted }
        XCTAssertEqual(uncompleted.count, 1)
        XCTAssertEqual(uncompleted.first?.weightKg, 38)
        XCTAssertEqual(uncompleted.first?.reps, 10)
    }

    func testReplaceExerciseUsesPrescription() throws {
        let sourceCatalog = ExerciseCatalog(
            canonicalName: "Barbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        let substituteCatalog = ExerciseCatalog(
            canonicalName: "Dumbbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .dumbbell
        )
        context.insert(sourceCatalog)
        context.insert(substituteCatalog)

        let prior = WorkoutSession(
            title: "Prior",
            startTime: .now.addingTimeInterval(-86_400),
            endTime: .now.addingTimeInterval(-85_000),
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(prior)
        let priorExercise = WorkoutExercise(
            exerciseTitle: substituteCatalog.canonicalName,
            order: 0,
            catalogEntry: substituteCatalog
        )
        priorExercise.session = prior
        prior.exercises.append(priorExercise)
        let priorSet = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 30,
            reps: 12
        )
        priorSet.exercise = priorExercise
        priorExercise.sets.append(priorSet)
        try context.save()

        let session = try store.startEmpty()
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: sourceCatalog,
            exerciseTitle: sourceCatalog.canonicalName
        )

        try store.replaceExercise(
            exercise,
            catalogEntry: substituteCatalog,
            exerciseTitle: substituteCatalog.canonicalName
        )

        XCTAssertEqual(exercise.exerciseTitle, "Dumbbell Bench Press")
        XCTAssertFalse(exercise.sets.isEmpty)
        XCTAssertEqual(exercise.sets.first?.weightKg, 30)
    }
}
