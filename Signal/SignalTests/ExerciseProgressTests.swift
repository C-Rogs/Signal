import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseProgressTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testSameSessionNotDuplicatedOnDoubleRecord() throws {
        let session = WorkoutSession(
            title: "Push",
            startTime: Date(),
            endTime: Date(),
            date: Calendar.current.startOfDay(for: Date()),
            source: "test"
        )
        context.insert(session)

        let catalog = ExerciseCatalog(
            canonicalName: "Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        context.insert(catalog)

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
            reps: 5
        )
        set.exercise = exercise
        exercise.sets.append(set)
        try context.save()

        try ExerciseProgressStore.recordSession(session, in: context)
        try ExerciseProgressStore.recordSession(session, in: context)

        let descriptor = FetchDescriptor<ExerciseProgress>()
        let rows = try context.fetch(descriptor)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.exerciseID, "Bench Press")
    }
}
