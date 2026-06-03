import SwiftData
import XCTest
@testable import Signal

@MainActor
final class WorkoutLiveSummaryTests: XCTestCase {
    func testComputeVolumeExcludesWarmupSets() throws {
        let session = WorkoutSession(
            title: "Test",
            startTime: Date(timeIntervalSince1970: 0),
            endTime: nil,
            date: Date(timeIntervalSince1970: 0),
            source: WorkoutSessionSource.live
        )
        let exercise = WorkoutExercise(exerciseTitle: "Squat", order: 0)
        exercise.session = session
        session.exercises.append(exercise)

        let warmup = SetEntry(
            setIndex: 0,
            setType: WorkoutSetType.warmup.storageValue,
            weightKg: 60,
            reps: 10,
            isCompleted: true
        )
        warmup.exercise = exercise

        let working = SetEntry(
            setIndex: 1,
            setType: WorkoutSetType.normal.storageValue,
            weightKg: 100,
            reps: 5,
            isCompleted: true
        )
        working.exercise = exercise
        exercise.sets = [warmup, working]

        let summary = WorkoutLiveSummary.compute(
            for: session,
            now: Date(timeIntervalSince1970: 600)
        )

        XCTAssertEqual(summary.volumeKg, 500, accuracy: 0.001)
        XCTAssertEqual(summary.completedSetCount, 2)
        XCTAssertEqual(summary.durationSeconds, 600)
    }
}
