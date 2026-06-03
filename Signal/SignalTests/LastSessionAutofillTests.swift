import SwiftData
import XCTest
@testable import Signal

@MainActor
final class LastSessionAutofillTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
    }

    func testTemplatesNeverCopyRPEFromLastSession() throws {
        let prior = WorkoutSession(
            title: "Prior",
            startTime: .now.addingTimeInterval(-86_400),
            endTime: .now.addingTimeInterval(-86_000),
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(prior)
        let exercise = WorkoutExercise(exerciseTitle: "Crunch", order: 0)
        exercise.session = prior
        prior.exercises.append(exercise)
        let set = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 20,
            reps: 12,
            rpe: 9
        )
        set.exercise = exercise
        exercise.sets.append(set)
        try context.save()

        let templates = try LastSessionAutofill.templates(
            catalogEntry: nil,
            exerciseTitle: "Crunch",
            mode: .strength,
            in: context
        )
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].weightKg, 20)
        XCTAssertEqual(templates[0].reps, 12)
        XCTAssertNil(templates[0].rpe)

        let previous = try LastSessionAutofill.previousSet(
            catalogEntry: nil,
            exerciseTitle: "Crunch",
            setIndex: 0,
            mode: .strength,
            in: context
        )
        XCTAssertEqual(previous?.rpe, 9)
    }
}
