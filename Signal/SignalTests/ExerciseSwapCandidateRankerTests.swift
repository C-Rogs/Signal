import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseSwapCandidateRankerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
    }

    func testBenchOccupiedPrefersDumbbellOrMachine() throws {
        let barbellBench = makeCatalog(
            name: "Barbell Bench Press",
            muscles: [.chest],
            pattern: .horizontalPush,
            equipment: .barbell,
            pickerDefault: true
        )
        let dumbbellBench = makeCatalog(
            name: "Dumbbell Bench Press",
            muscles: [.chest],
            pattern: .horizontalPush,
            equipment: .dumbbell,
            pickerDefault: true
        )
        let machinePress = makeCatalog(
            name: "Chest Press Machine",
            muscles: [.chest],
            pattern: .horizontalPush,
            equipment: .machine,
            pickerDefault: true
        )
        let legPress = makeCatalog(
            name: "Leg Press",
            muscles: [.quads],
            pattern: .squat,
            equipment: .machine
        )
        context.insert(barbellBench)
        context.insert(dumbbellBench)
        context.insert(machinePress)
        context.insert(legPress)
        try context.save()

        let sourceExercise = WorkoutExercise(
            exerciseTitle: barbellBench.canonicalName,
            order: 0,
            catalogEntry: barbellBench
        )

        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        let ranked = ExerciseSwapCandidateRanker.rank(
            source: sourceExercise,
            constraint: "bench is occupied",
            catalog: catalog,
            in: context
        )

        XCTAssertFalse(ranked.isEmpty)
        let names = ranked.map { $0.catalogEntry.canonicalName }
        XCTAssertTrue(names.contains("Dumbbell Bench Press") || names.contains("Chest Press Machine"))
        XCTAssertFalse(names.contains("Barbell Bench Press"))
        XCTAssertFalse(names.contains("Leg Press"))
    }

    func testCapsAtEightCandidates() throws {
        for index in 0..<12 {
            context.insert(
                makeCatalog(
                    name: "Press Variant \(index)",
                    muscles: [.chest],
                    pattern: .horizontalPush,
                    equipment: index % 2 == 0 ? .dumbbell : .cable
                )
            )
        }
        let sourceCatalog = makeCatalog(
            name: "Barbell Bench Press",
            muscles: [.chest],
            pattern: .horizontalPush,
            equipment: .barbell
        )
        context.insert(sourceCatalog)
        try context.save()

        let source = WorkoutExercise(
            exerciseTitle: sourceCatalog.canonicalName,
            order: 0,
            catalogEntry: sourceCatalog
        )
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        let ranked = ExerciseSwapCandidateRanker.rank(
            source: source,
            constraint: "",
            catalog: catalog,
            in: context
        )
        XCTAssertLessThanOrEqual(ranked.count, ExerciseSwapCandidateRanker.maxCandidates)
    }

    func testConstraintParserExcludesBarbellWhenBenchOccupied() {
        let excluded = ExerciseSwapConstraintParser.excludedEquipment(from: "The bench is occupied")
        XCTAssertTrue(excluded.contains(.barbell))
        XCTAssertTrue(excluded.contains(.smith))
    }

    private func makeCatalog(
        name: String,
        muscles: [Muscle],
        pattern: MovementPattern,
        equipment: ExerciseEquipment,
        pickerDefault: Bool = false
    ) -> ExerciseCatalog {
        ExerciseCatalog(
            canonicalName: name,
            primaryMuscles: muscles,
            secondaryMuscles: [],
            movementPattern: pattern,
            equipment: equipment,
            isPickerDefault: pickerDefault
        )
    }
}
