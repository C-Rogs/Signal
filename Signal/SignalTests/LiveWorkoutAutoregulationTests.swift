import XCTest
@testable import Signal

final class LiveWorkoutAutoregulationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Live HR set cue

    func testRestNudgeWhenElevatedAndFresh() {
        let sampledAt = now.addingTimeInterval(-10)
        let message = LiveHRCueEvaluator.restNudgeAfterSet(bpm: 158, sampledAt: sampledAt, now: now)
        XCTAssertEqual(message, "Heart rate still 158. Take the full rest.")
    }

    func testRestNudgeSuppressedBelowThreshold() {
        let sampledAt = now.addingTimeInterval(-5)
        XCTAssertNil(LiveHRCueEvaluator.restNudgeAfterSet(bpm: 149, sampledAt: sampledAt, now: now))
    }

    func testRestNudgeSuppressedWhenStale() {
        let sampledAt = now.addingTimeInterval(-60)
        XCTAssertNil(LiveHRCueEvaluator.restNudgeAfterSet(bpm: 160, sampledAt: sampledAt, now: now))
    }

    func testComposedCueAppendsHRLine() {
        let sampledAt = now.addingTimeInterval(-5)
        let composed = LiveSetCueComposer.compose(
            tierMessage: "On plan.",
            loadNudge: nil,
            heartRateBPM: 152,
            heartRateSampledAt: sampledAt,
            now: now
        )
        XCTAssertEqual(composed, "On plan.\nHeart rate still 152. Take the full rest.")
    }

    func testComposedCueTierOnlyWhenHRUnavailable() {
        XCTAssertEqual(
            LiveHRCueEvaluator.composedSetCue(
                tierMessage: "On plan.",
                heartRateBPM: nil,
                heartRateSampledAt: nil,
                now: now
            ),
            "On plan."
        )
    }

    // MARK: - Dynamic rest extension

    func testDynamicRestExtendsOnceWhenElevated() {
        let exerciseID = "exercise-1"
        let restEndsAt = now.addingTimeInterval(60)
        let sampledAt = now.addingTimeInterval(-3)
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: 155,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: DynamicRestState()
        )
        let decision = DynamicRestTimerEvaluator.evaluate(input)
        XCTAssertEqual(decision?.extensionSeconds, 30)
        XCTAssertEqual(decision?.notice, "+30s, HR still 155")
        XCTAssertEqual(decision?.newState.extensionCount, 1)
    }

    func testDynamicRestRespectsMaxExtensions() {
        let exerciseID = "exercise-1"
        let restEndsAt = now.addingTimeInterval(90)
        let sampledAt = now.addingTimeInterval(-2)
        var state = DynamicRestState(trackedExerciseID: exerciseID, extensionCount: 2)
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: 160,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: state
        )
        XCTAssertNil(DynamicRestTimerEvaluator.evaluate(input))

        state.extensionCount = 1
        state.lastExtensionAt = now.addingTimeInterval(-25)
        let second = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: 160,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: state
        )
        XCTAssertNotNil(DynamicRestTimerEvaluator.evaluate(second))
    }

    func testDynamicRestThrottlesRapidExtensions() {
        let exerciseID = "exercise-1"
        let restEndsAt = now.addingTimeInterval(90)
        let sampledAt = now.addingTimeInterval(-2)
        let state = DynamicRestState(
            trackedExerciseID: exerciseID,
            extensionCount: 1,
            lastExtensionAt: now.addingTimeInterval(-5)
        )
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: 162,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: state
        )
        XCTAssertNil(DynamicRestTimerEvaluator.evaluate(input))
    }

    func testDynamicRestSkipsWhenRestAlmostDone() {
        let exerciseID = "exercise-1"
        let restEndsAt = now.addingTimeInterval(5)
        let sampledAt = now.addingTimeInterval(-2)
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: 170,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: DynamicRestState()
        )
        XCTAssertNil(DynamicRestTimerEvaluator.evaluate(input))
    }

    func testDynamicRestResetsWhenExerciseChanges() {
        let restEndsAt = now.addingTimeInterval(60)
        let sampledAt = now.addingTimeInterval(-2)
        let prior = DynamicRestState(trackedExerciseID: "old", extensionCount: 2)
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: "new",
            heartRateBPM: 155,
            heartRateSampledAt: sampledAt,
            now: now,
            restEndsAt: restEndsAt,
            state: prior
        )
        let decision = DynamicRestTimerEvaluator.evaluate(input)
        XCTAssertEqual(decision?.newState.extensionCount, 1)
        XCTAssertEqual(decision?.newState.trackedExerciseID, "new")
    }
}
