import XCTest
@testable import Signal

final class CueEngineTests: XCTestCase {
    private let sessionID = "session-a"
    private let exerciseID = "exercise-a"

    private func input(
        completed: SetCueSnapshot,
        prior: SetCueSnapshot? = nil,
        allCompleted: [SetCueSnapshot]? = nil,
        lastSession: SetCueSnapshot? = nil,
        targetReps: Int? = nil,
        sessionID: String = "session-a",
        exerciseID: String = "exercise-a"
    ) -> ExerciseCueInput {
        ExerciseCueInput(
            sessionID: sessionID,
            exerciseID: exerciseID,
            mode: .strength,
            completedSet: completed,
            priorSetInSession: prior,
            allCompletedSets: allCompleted ?? [completed],
            lastSessionSet: lastSession,
            targetReps: targetReps ?? lastSession?.reps
        )
    }

    private func working(
        setIndex: Int = 0,
        weightKg: Double? = 100,
        reps: Int? = 8,
        rpe: Double? = 8
    ) -> SetCueSnapshot {
        SetCueSnapshot(
            setIndex: setIndex,
            weightKg: weightKg,
            reps: reps,
            rpe: rpe,
            isWarmup: false
        )
    }

    // MARK: - Tier branches

    func testSmashedTier() {
        let completed = working(reps: 10, rpe: 5)
        let last = working(reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last, targetReps: 8)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .smashed)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(
            ["Had more in you.", "Way above plan.", "Add load next set.", "One more rep next time."]
                .contains(message)
        )
    }

    func testSmashedNudgeWhenNoPR() {
        let completed = working(weightKg: 100, reps: 10, rpe: 5)
        let last = working(weightKg: 100, reps: 10, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last, targetReps: 8)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .smashed)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(["Add load next set.", "One more rep next time."].contains(message))
    }

    func testStrongPRByLoad() {
        let completed = working(weightKg: 105, reps: 8, rpe: 8)
        let last = working(weightKg: 100, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .strongPR)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(["Big jump.", "Crushed it.", "Bank that."].contains(message))
    }

    func testStrongPRByReps() {
        let completed = working(weightKg: 100, reps: 10, rpe: 8)
        let last = working(weightKg: 100, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .strongPR)
    }

    func testSmallPRByLoad() {
        let completed = working(weightKg: 102.5, reps: 8, rpe: 8)
        let last = working(weightKg: 100, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .smallPR)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(["New best.", "Up from last time.", "Progress."].contains(message))
    }

    func testSmallPRByReps() {
        let completed = working(weightKg: 100, reps: 9, rpe: 8)
        let last = working(weightKg: 100, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .smallPR)
    }

    func testOnTrackTier() {
        let completed = working(reps: 8, rpe: 7.5)
        let last = working(reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: last, targetReps: 8)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .onTrack)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(
            ["Dialed in.", "On plan.", "Right where you want it.", "Clean set."].contains(message)
        )
    }

    func testHardButOKFirstHighRPE() {
        let completed = working(setIndex: 0, rpe: 9.5)
        let cueInput = input(completed: completed)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .hardButOK)
    }

    func testFatigueLoadDrop() {
        let prior = working(setIndex: 0, weightKg: 100, reps: 8, rpe: 8)
        let completed = working(setIndex: 1, weightKg: 95, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, prior: prior, allCompleted: [prior, completed])
        XCTAssertEqual(CueEngine.tier(for: cueInput), .fatigue)
    }

    func testFatigueRepsDrop() {
        let prior = working(setIndex: 0, weightKg: 100, reps: 10, rpe: 8)
        let completed = working(setIndex: 1, weightKg: 100, reps: 7, rpe: 8)
        let cueInput = input(completed: completed, prior: prior, allCompleted: [prior, completed])
        XCTAssertEqual(CueEngine.tier(for: cueInput), .fatigue)
    }

    func testStopAfterTwoHardSets() {
        let first = working(setIndex: 0, rpe: 9)
        let second = working(setIndex: 1, rpe: 10)
        let cueInput = input(completed: second, allCompleted: [first, second])
        XCTAssertEqual(CueEngine.tier(for: cueInput), .stop)
        let message = CueEngine.cue(for: cueInput)
        XCTAssertTrue(
            ["Enough quality sets.", "Stop here, volume is in.", "Bank it."].contains(message)
        )
    }

    func testNeutralWhenInsufficientData() {
        let completed = working(rpe: nil)
        let cueInput = input(completed: completed, lastSession: nil, targetReps: nil)
        XCTAssertEqual(CueEngine.tier(for: cueInput), .neutral)
        XCTAssertEqual(CueEngine.cue(for: cueInput), "Set logged.")
    }

    func testNilLastSessionFallsThroughWithoutCrash() {
        let completed = working(weightKg: 105, reps: 8, rpe: 8)
        let cueInput = input(completed: completed, lastSession: nil, targetReps: nil)
        XCTAssertNotNil(CueEngine.cue(for: cueInput))
        XCTAssertEqual(CueEngine.tier(for: cueInput), .neutral)
    }

    func testStrongPRBeatsFatigue() {
        let prior = working(setIndex: 0, weightKg: 100, reps: 10, rpe: 8)
        let completed = working(setIndex: 1, weightKg: 105, reps: 7, rpe: 8)
        let last = working(weightKg: 100, reps: 8, rpe: 8)
        let cueInput = input(
            completed: completed,
            prior: prior,
            allCompleted: [prior, completed],
            lastSession: last
        )
        XCTAssertEqual(CueEngine.tier(for: cueInput), .strongPR)
    }

    // MARK: - Hash rotation and determinism

    func testHashRotationDifferentSetIndex() {
        let base = input(completed: working(setIndex: 0, rpe: 7.5), lastSession: working(reps: 8), targetReps: 8)
        let other = input(completed: working(setIndex: 1, rpe: 7.5), lastSession: working(reps: 8), targetReps: 8)
        XCTAssertEqual(CueEngine.tier(for: base), .onTrack)
        XCTAssertEqual(CueEngine.tier(for: other), .onTrack)
        let msg0 = CueEngine.message(for: .onTrack, input: base)
        let msg1 = CueEngine.message(for: .onTrack, input: other)
        XCTAssertNotEqual(msg0, msg1)
    }

    func testDeterministicSameInputs() {
        let completed = working(setIndex: 2, rpe: 7)
        let cueInput = input(completed: completed, lastSession: working(reps: 8), targetReps: 8)
        let first = CueEngine.cue(for: cueInput)
        let second = CueEngine.cue(for: cueInput)
        XCTAssertEqual(first, second)
    }

    func testSelectionIndexStable() {
        let a = CueEngine.selectionIndex(
            sessionID: sessionID,
            exerciseID: exerciseID,
            setIndex: 0,
            tier: .onTrack,
            poolSize: 4
        )
        let b = CueEngine.selectionIndex(
            sessionID: sessionID,
            exerciseID: exerciseID,
            setIndex: 0,
            tier: .onTrack,
            poolSize: 4
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - Mode guards

    func testWarmupSetReturnsNoCue() {
        let warmup = SetCueSnapshot(setIndex: 0, weightKg: 40, reps: 10, rpe: 5, isWarmup: true)
        XCTAssertNil(CueEngine.cue(for: input(completed: warmup)))
    }

    func testCardioModeReturnsNoCue() {
        let cardio = ExerciseCueInput(
            sessionID: sessionID,
            exerciseID: exerciseID,
            mode: .cardio,
            completedSet: working(),
            priorSetInSession: nil,
            allCompletedSets: [working()],
            lastSessionSet: nil,
            targetReps: nil
        )
        XCTAssertNil(CueEngine.cue(for: cardio))
    }

    func testDefaultRIRTarget() {
        XCTAssertEqual(CueEngine.defaultRIRTarget, 2)
        let cueInput = input(completed: working())
        XCTAssertEqual(cueInput.defaultRIRTarget, 2)
    }
}
