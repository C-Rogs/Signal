import XCTest
@testable import Signal

final class RestTimerFeedbackEvaluatorTests: XCTestCase {
    func testRestStartedOnNewActiveTimer() {
        var state = RestTimerFeedbackState()
        let actions = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 90)
        XCTAssertEqual(actions, [.restStarted])
    }

    func testCountdownFiresAtThreeTwoOneOnceEach() {
        var state = RestTimerFeedbackState()
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 90)
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 4), [])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 3), [.countdown(second: 3)])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 3), [])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 2), [.countdown(second: 2)])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 1), [.countdown(second: 1)])
    }

    func testRestEndedWhenActiveBecomesNil() {
        var state = RestTimerFeedbackState()
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 2)
        XCTAssertEqual(state.advance(activeExerciseID: nil, remainingSeconds: nil), [.restEnded])
    }

    func testSkipSuppressesRestEnded() {
        var state = RestTimerFeedbackState()
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 2)
        state.markUserSkipped()
        XCTAssertEqual(state.advance(activeExerciseID: nil, remainingSeconds: nil), [])
        XCTAssertNil(state.trackedExerciseID)
    }

    func testAcknowledgeRestStartedPreventsDuplicateRestStarted() {
        var state = RestTimerFeedbackState()
        state.acknowledgeRestStarted(exerciseID: "exercise-a")
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 60), [])
    }

    func testMilestoneFiresAtThirtyAndTenOnceEach() {
        var state = RestTimerFeedbackState()
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 90)
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 31), [])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 30), [.milestone(second: 30)])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 30), [])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 10), [.milestone(second: 10)])
    }

    func testCountdownFiresAtZeroWhileTimerStillActive() {
        var state = RestTimerFeedbackState()
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 2)
        _ = state.advance(activeExerciseID: "exercise-a", remainingSeconds: 1)
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 0), [.countdown(second: 0)])
        XCTAssertEqual(state.advance(activeExerciseID: "exercise-a", remainingSeconds: 0), [])
    }
}
