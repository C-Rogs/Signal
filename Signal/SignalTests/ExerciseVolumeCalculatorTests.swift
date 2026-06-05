import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseVolumeCalculatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testAverageWorkingSetVolumeUsesLastEightSessions() throws {
        let catalog = ExerciseCatalog(
            canonicalName: "Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        context.insert(catalog)

        for index in 0..<10 {
            let session = WorkoutSession(
                title: "Session \(index)",
                startTime: Date().addingTimeInterval(Double(-index) * 86_400),
                endTime: Date().addingTimeInterval(Double(-index) * 86_400 + 3600),
                date: Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-index) * 86_400)),
                source: "test"
            )
            context.insert(session)

            let exercise = WorkoutExercise(
                exerciseTitle: "Bench Press",
                order: 0,
                catalogEntry: catalog
            )
            exercise.session = session
            session.exercises.append(exercise)

            let set = SetEntry(
                setIndex: 0,
                setType: WorkoutSetType.normal.storageValue,
                weightKg: 100,
                reps: 5 + index
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
        try context.save()

        let average = try XCTUnwrap(
            ExerciseVolumeCalculator.averageWorkingSetVolume(
                catalogEntry: catalog,
                exerciseTitle: "Bench Press",
                sessionLimit: 8,
                in: context
            )
        )

        XCTAssertEqual(average, 850, accuracy: 0.01)
    }

    func testBestLoadPRPicksHighestWeightTimesReps() throws {
        let catalog = ExerciseCatalog(
            canonicalName: "Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes],
            movementPattern: .squat,
            equipment: .barbell
        )
        context.insert(catalog)

        let session = WorkoutSession(
            title: "Leg day",
            startTime: Date(),
            endTime: Date(),
            date: Calendar.current.startOfDay(for: Date()),
            source: "test"
        )
        context.insert(session)

        let exercise = WorkoutExercise(exerciseTitle: "Squat", order: 0, catalogEntry: catalog)
        exercise.session = session
        session.exercises.append(exercise)

        let lighter = SetEntry(setIndex: 0, setType: WorkoutSetType.normal.storageValue, weightKg: 100, reps: 5)
        lighter.exercise = exercise
        let heavier = SetEntry(setIndex: 1, setType: WorkoutSetType.normal.storageValue, weightKg: 140, reps: 3)
        heavier.exercise = exercise
        exercise.sets.append(contentsOf: [lighter, heavier])
        try context.save()

        let pr = try ExerciseVolumeCalculator.bestLoadPR(
            catalogEntry: catalog,
            exerciseTitle: "Squat",
            in: context
        )

        XCTAssertEqual(pr?.weightKg, 100)
        XCTAssertEqual(pr?.reps, 5)
    }
}
