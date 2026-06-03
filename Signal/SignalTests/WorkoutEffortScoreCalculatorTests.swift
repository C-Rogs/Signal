import SwiftData
import XCTest
@testable import Signal

@MainActor
final class WorkoutEffortScoreCalculatorTests: XCTestCase {
    func testMeanExcludesWarmupAndIncompleteSets() throws {
        let session = WorkoutSession(
            title: "Test",
            startTime: .now,
            endTime: .now,
            date: .now,
            source: WorkoutSessionSource.live
        )
        let exercise = WorkoutExercise(exerciseTitle: "Press", order: 0)
        exercise.session = session
        session.exercises.append(exercise)

        let warmup = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.warmup.storageValue,
            rpe: 5,
            isCompleted: true
        )
        warmup.exercise = exercise

        let incomplete = SetEntry(
            setIndex: 1,
            setType: WorkoutSetType.normal.storageValue,
            rpe: 9,
            isCompleted: false
        )
        incomplete.exercise = exercise

        let workingA = SetEntry(
            setIndex: 2,
            setType: WorkoutSetType.normal.storageValue,
            rpe: 8,
            isCompleted: true
        )
        workingA.exercise = exercise

        let workingB = SetEntry(
            setIndex: 3,
            setType: WorkoutSetType.normal.storageValue,
            rpe: 10,
            isCompleted: true
        )
        workingB.exercise = exercise
        exercise.sets = [warmup, incomplete, workingA, workingB]

        XCTAssertTrue(WorkoutEffortScoreCalculator.hasWorkingSetRPE(in: session))
        XCTAssertEqual(WorkoutEffortScoreCalculator.meanScore(for: session), 9)
    }

    func testClampAndRound() {
        XCTAssertEqual(WorkoutEffortScoreCalculator.clampAndRound(0.4), 1)
        XCTAssertEqual(WorkoutEffortScoreCalculator.clampAndRound(10.6), 10)
        XCTAssertEqual(WorkoutEffortScoreCalculator.clampAndRound(7.4), 7)
        XCTAssertEqual(WorkoutEffortScoreCalculator.clampAndRound(7.5), 8)
    }

    func testNoRPERequiresManualEffort() {
        let session = WorkoutSession(
            title: "Test",
            startTime: .now,
            endTime: .now,
            date: .now,
            source: WorkoutSessionSource.live
        )
        XCTAssertFalse(WorkoutEffortScoreCalculator.hasWorkingSetRPE(in: session))
        XCTAssertNil(WorkoutEffortScoreCalculator.meanScore(for: session))
    }
}
