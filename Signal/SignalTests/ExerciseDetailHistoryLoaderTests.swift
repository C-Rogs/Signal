import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseDetailHistoryLoaderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testRecentSessionsIncludeRPEInSummary() throws {
        let catalog = ExerciseCatalog(
            canonicalName: "Lat Pulldown",
            primaryMuscles: [.lats],
            secondaryMuscles: [.biceps],
            movementPattern: .verticalPull,
            equipment: .cable
        )
        context.insert(catalog)

        let session = WorkoutSession(
            title: "Pull",
            startTime: Date(),
            endTime: Date(),
            date: Calendar.current.startOfDay(for: Date()),
            source: "test"
        )
        context.insert(session)

        let exercise = WorkoutExercise(
            exerciseTitle: "Lat Pulldown (Cable)",
            order: 0,
            catalogEntry: catalog
        )
        exercise.session = session
        session.exercises.append(exercise)

        let set = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 59,
            reps: 10,
            rpe: 8.5
        )
        set.exercise = exercise
        exercise.sets.append(set)
        try context.save()

        let formatter = DisplayUnitFormatter(preferences: UnitPreferences())
        let sessions = try ExerciseDetailHistoryLoader.loadRecentSessions(
            catalogEntry: catalog,
            exerciseTitle: "Lat Pulldown (Cable)",
            limit: 5,
            formatter: formatter,
            in: context
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].setSummaries.joined().contains("RPE 8.5"))
    }
}
