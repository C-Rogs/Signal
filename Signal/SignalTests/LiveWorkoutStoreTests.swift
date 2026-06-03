import SwiftData
import XCTest
@testable import Signal

@MainActor
final class LiveWorkoutStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: LiveWorkoutStore!

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveWorkoutStoreTests-\(UUID().uuidString).sqlite")
        let configuration = ModelConfiguration(url: url)
        container = try ModelContainer(for: SignalModelContainer.schema, configurations: [configuration])
        context = ModelContext(container)
        store = LiveWorkoutStore(context: context)
    }

    func testStartEmptyAndRelaunchFindsActiveSession() throws {
        let session = try store.startEmpty()
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: nil,
            exerciseTitle: "Pull Up"
        )
        let set = exercise.sets.sorted { $0.setIndex < $1.setIndex }.first!
        try store.commitSetFields(
            set,
            fields: SetFieldCommit(
                setType: WorkoutSetType.normal.storageValue,
                weightKg: nil,
                reps: 8,
                distanceKm: nil,
                durationSeconds: nil,
                rpe: nil
            )
        )
        try store.toggleSetComplete(set, exercise: exercise, completed: true)

        let relaunched = LiveWorkoutStore(context: ModelContext(container))
        let active = try relaunched.activeSession()
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.exercises.count, 1)
        let restoredSet = active?.exercises.first?.sets.first
        XCTAssertEqual(restoredSet?.reps, 8)
        XCTAssertNil(restoredSet?.weightKg)
        XCTAssertTrue(restoredSet?.isCompleted == true)
    }

    func testCommitOnBlurPersistsWeight() throws {
        let session = try store.startEmpty()
        let catalog = ExerciseCatalog(
            canonicalName: "Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        context.insert(catalog)
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: catalog,
            exerciseTitle: catalog.canonicalName
        )
        let set = exercise.sets.first!

        try store.commitSetFields(
            set,
            fields: SetFieldCommit(
                setType: WorkoutSetType.normal.storageValue,
                weightKg: 100,
                reps: 5,
                distanceKm: nil,
                durationSeconds: nil,
                rpe: 8
            )
        )

        let relaunched = LiveWorkoutStore(context: ModelContext(container))
        let active = try relaunched.activeSession()
        let restored = active?.exercises.first?.sets.first
        XCTAssertEqual(restored?.weightKg, 100)
        XCTAssertEqual(restored?.reps, 5)
    }

    func testSupersetLinkAndBreak() throws {
        let session = try store.startEmpty()
        let a = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "A")
        let b = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "B")
        try store.linkSuperset(a, b)
        XCTAssertEqual(a.supersetId, b.supersetId)
        try store.breakSuperset(for: a, in: session)
        XCTAssertNil(a.supersetId)
        XCTAssertNil(b.supersetId)
    }

    func testRestTimerPersists() throws {
        let session = try store.startEmpty()
        let exercise = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "Curl")
        try store.startRestTimer(for: exercise, durationSeconds: 60)
        XCTAssertNotNil(exercise.restTimerEndsAt)

        let relaunched = LiveWorkoutStore(context: ModelContext(container))
        let active = try relaunched.activeSession()
        XCTAssertNotNil(active?.exercises.first?.restTimerEndsAt)
    }

    func testFinishAndDiscard() throws {
        let session = try store.startEmpty()
        try store.finishSession(session)
        XCTAssertNotNil(session.endTime)
        XCTAssertNil(try store.activeSession())

        let session2 = try store.startEmpty()
        try store.discardSession(session2)
        XCTAssertNil(try store.activeSession())
    }

    func testCompleteWithoutBlurPersistsWeight() throws {
        let session = try store.startEmpty()
        let catalog = ExerciseCatalog(
            canonicalName: "Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes],
            movementPattern: .squat,
            equipment: .barbell
        )
        context.insert(catalog)
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: catalog,
            exerciseTitle: catalog.canonicalName
        )
        let set = exercise.sets.first!

        let uiFields = SetFieldCommit(
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 140,
            reps: 5,
            distanceKm: nil,
            durationSeconds: nil,
            rpe: nil
        )
        try store.commitSetFields(set, fields: uiFields)
        try store.toggleSetComplete(set, exercise: exercise, completed: true)

        let relaunched = LiveWorkoutStore(context: ModelContext(container))
        let active = try relaunched.activeSession()
        let restored = active?.exercises.first?.sets.first
        XCTAssertEqual(restored?.weightKg, 140)
        XCTAssertEqual(restored?.reps, 5)
        XCTAssertTrue(restored?.isCompleted == true)
    }

    func testFinishSessionPersistsAllExercises() throws {
        let session = try store.startEmpty()
        _ = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "A")
        _ = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "B")
        _ = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "C")
        try store.finishSession(session)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil }
        )
        let completed = try verifyContext.fetch(descriptor)
        let sessionID = try XCTUnwrap(completed.first?.persistentModelID)
        let allExercises = try verifyContext.fetch(FetchDescriptor<WorkoutExercise>())
        let linked = allExercises.filter { $0.session?.persistentModelID == sessionID }
        XCTAssertEqual(linked.count, 3)
    }

    func testSetTimestampsOnEditAndComplete() throws {
        let session = try store.startEmpty()
        let exercise = try store.addExercise(to: session, catalogEntry: nil, exerciseTitle: "Row")
        let first = try XCTUnwrap(exercise.sets.sorted { $0.setIndex < $1.setIndex }.first)
        _ = try store.addSet(to: exercise)
        let second = try XCTUnwrap(
            exercise.sets.sorted { $0.setIndex < $1.setIndex }.last
        )

        XCTAssertNil(first.startedAt)
        try store.commitSetFields(
            first,
            fields: SetFieldCommit(
                setType: WorkoutSetType.normal.storageValue,
                weightKg: 60,
                reps: 8,
                distanceKm: nil,
                durationSeconds: nil,
                rpe: 7
            )
        )
        XCTAssertNotNil(first.startedAt)
        XCTAssertNil(first.completedAt)

        try store.toggleSetComplete(first, exercise: exercise, completed: true)
        XCTAssertNotNil(first.completedAt)
        XCTAssertNotNil(second.startedAt)

        try store.toggleSetComplete(first, exercise: exercise, completed: false)
        XCTAssertNil(first.completedAt)

        let relaunched = LiveWorkoutStore(context: ModelContext(container))
        let active = try relaunched.activeSession()
        let restoredFirst = active?.exercises.first?.sets.sorted { $0.setIndex < $1.setIndex }.first
        XCTAssertNotNil(restoredFirst?.startedAt)
        XCTAssertNil(restoredFirst?.completedAt)
    }

    func testCardioSetFields() throws {
        let session = try store.startEmpty()
        let catalog = ExerciseCatalog(
            canonicalName: "Running",
            primaryMuscles: [.fullBody],
            secondaryMuscles: [],
            movementPattern: .cardio,
            equipment: .other
        )
        context.insert(catalog)
        let exercise = try store.addExercise(
            to: session,
            catalogEntry: catalog,
            exerciseTitle: catalog.canonicalName
        )
        let set = exercise.sets.first!
        try store.commitSetFields(
            set,
            fields: SetFieldCommit(
                setType: WorkoutSetType.normal.storageValue,
                weightKg: nil,
                reps: nil,
                distanceKm: 5,
                durationSeconds: 1800,
                rpe: nil
            )
        )
        XCTAssertEqual(set.distanceKm, 5)
        XCTAssertEqual(set.durationSeconds, 1800)
    }
}
