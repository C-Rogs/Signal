import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseSwapLoadPrescriptionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
    }

    func testAppliesProgressionIncreaseToSubstitute() throws {
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

        seedCompletedSession(
            title: "Dumbbell Bench Press",
            catalog: substituteCatalog,
            sets: [(40, 10), (40, 10)]
        )
        seedCompletedSession(
            title: "Barbell Bench Press",
            catalog: sourceCatalog,
            sets: [(97.5, 5), (97.5, 5)]
        )
        try context.save()

        let liveSession = WorkoutSession(
            title: "Push",
            startTime: .now,
            endTime: nil,
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(liveSession)
        let sourceExercise = WorkoutExercise(
            exerciseTitle: sourceCatalog.canonicalName,
            order: 0,
            catalogEntry: sourceCatalog
        )
        sourceExercise.session = liveSession
        liveSession.exercises.append(sourceExercise)

        for (index, weight) in [(0, 100.0), (1, 100.0)] {
            let set = SetEntry(
                setIndex: index,
                setType: WorkoutSetType.normal.storageValue,
                weightKg: weight,
                reps: 5
            )
            set.exercise = sourceExercise
            sourceExercise.sets.append(set)
        }
        try context.save()

        let plan = try ExerciseSwapLoadPrescription.build(
            source: sourceExercise,
            substitute: substituteCatalog,
            recoveryScore: makeRecoveryScore(value: 75),
            personalReadiness: nil,
            deloadActive: false,
            in: context
        )

        XCTAssertTrue(plan.substituteHasHistory)
        XCTAssertNil(plan.noHistoryNote)
        XCTAssertEqual(plan.progressionIntent, .increase(byKg: 2.5))
        let working = plan.sets.filter {
            WorkoutSetType(storageValue: $0.setType) != .warmup
        }
        XCTAssertEqual(working.first?.weightKg, 42.5)
    }

    func testNilWeightsWhenSubstituteHasNoHistory() throws {
        let sourceCatalog = ExerciseCatalog(
            canonicalName: "Barbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .barbell
        )
        let substituteCatalog = ExerciseCatalog(
            canonicalName: "Machine Chest Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush,
            equipment: .machine
        )
        context.insert(sourceCatalog)
        context.insert(substituteCatalog)

        let liveSession = WorkoutSession(
            title: "Push",
            startTime: .now,
            endTime: nil,
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(liveSession)
        let sourceExercise = WorkoutExercise(
            exerciseTitle: sourceCatalog.canonicalName,
            order: 0,
            catalogEntry: sourceCatalog
        )
        sourceExercise.session = liveSession
        liveSession.exercises.append(sourceExercise)
        let set = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 80,
            reps: 8
        )
        set.exercise = sourceExercise
        sourceExercise.sets.append(set)
        try context.save()

        let plan = try ExerciseSwapLoadPrescription.build(
            source: sourceExercise,
            substitute: substituteCatalog,
            recoveryScore: nil,
            personalReadiness: nil,
            deloadActive: false,
            in: context
        )

        XCTAssertFalse(plan.substituteHasHistory)
        XCTAssertEqual(plan.noHistoryNote, SwapSetPlan.noHistoryMessage)
        XCTAssertNil(plan.sets.first?.weightKg)
        XCTAssertEqual(plan.sets.first?.reps, 8)
    }

    private func makeRecoveryScore(value: Double) -> RecoveryScore {
        RecoveryScore(
            value: value,
            hrvClassification: .withinBand,
            hrvAnalysis: nil,
            rhrDelta: nil,
            sleepDelta: nil,
            confidence: .medium,
            breakdown: RecoveryScoreBreakdown(hrvTerm: 0, rhrTerm: 0, sleepTerm: 0, total: value),
            todayHRV: nil,
            todayRestingHR: nil
        )
    }

    private func seedCompletedSession(
        title: String,
        catalog: ExerciseCatalog,
        sets: [(Double, Int)]
    ) {
        let session = WorkoutSession(
            title: title,
            startTime: .now.addingTimeInterval(-86_400),
            endTime: .now.addingTimeInterval(-85_000),
            date: .now,
            source: WorkoutSessionSource.live
        )
        context.insert(session)
        let exercise = WorkoutExercise(
            exerciseTitle: catalog.canonicalName,
            order: 0,
            catalogEntry: catalog
        )
        exercise.session = session
        session.exercises.append(exercise)
        for (index, pair) in sets.enumerated() {
            let set = SetEntry(
                setIndex: index,
                setType: WorkoutSetType.normal.storageValue,
                weightKg: pair.0,
                reps: pair.1
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
    }
}
