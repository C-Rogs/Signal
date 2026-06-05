import SwiftData
import XCTest
@testable import Signal

@MainActor
final class WorkoutSwapFMSelectorTests: XCTestCase {
    func testSuggestFallsBackWhenModelUnavailable() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

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
            equipment: .dumbbell,
            isPickerDefault: true
        )
        context.insert(sourceCatalog)
        context.insert(substituteCatalog)
        try context.save()

        let source = WorkoutExercise(
            exerciseTitle: sourceCatalog.canonicalName,
            order: 0,
            catalogEntry: sourceCatalog
        )
        let candidates = [
            ExerciseSwapCandidate(catalogEntry: substituteCatalog, score: 40),
        ]

        let suggestion = await WorkoutSwapFMSelector.suggest(
            source: source,
            constraint: "bench is occupied",
            candidates: candidates,
            recoveryChip: nil
        )

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.substitute.canonicalName, "Dumbbell Bench Press")
        XCTAssertFalse(suggestion?.rationale.isEmpty ?? true)
    }
}
