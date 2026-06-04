import XCTest
@testable import Signal

final class LiveLoadAutoregulationTests: XCTestCase {
    private func recoveryScore(value: Double) -> RecoveryScore {
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

    private func workingSet(rpe: Double, reps: Int = 10) -> SetCueSnapshot {
        SetCueSnapshot(setIndex: 1, weightKg: 100, reps: reps, rpe: rpe, isWarmup: false)
    }

    private func input(
        recoveryValue: Double,
        rpe: Double,
        targetRIR: Int = 2,
        targetReps: Int? = 10,
        reps: Int = 10
    ) -> LiveLoadCueInput {
        LiveLoadCueInput(
            recoveryScore: recoveryScore(value: recoveryValue),
            completedSet: workingSet(rpe: rpe, reps: reps),
            targetRIR: targetRIR,
            targetReps: targetReps
        )
    }

    // MARK: - Load policy

    func testLowRecoverySuppressesAddLoadOnEasySet() {
        let message = LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 35, rpe: 5))
        XCTAssertEqual(message, "Recovery low. Hold weight.")
        XCTAssertFalse(message?.contains("Add") ?? true)
    }

    func testHighRecoveryEasySetAtTargetRIRSuggestsIncrease() {
        let message = LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 75, rpe: 6, targetRIR: 2, targetReps: 10, reps: 10))
        XCTAssertEqual(message, "Easy set at target RIR. Add 2.5 kg next set.")
    }

    func testHighRPESuggestsHoldRegardlessOfRecovery() {
        let low = LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 35, rpe: 9.5))
        let high = LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 80, rpe: 10))
        XCTAssertEqual(low, "RPE 9+. Stay at this weight for remaining sets.")
        XCTAssertEqual(high, "RPE 9+. Stay at this weight for remaining sets.")
    }

    func testModerateRecoveryNoLoadNudge() {
        XCTAssertNil(LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 55, rpe: 6)))
    }

    func testHighRecoveryHardSetNoAddNudge() {
        XCTAssertNil(LiveLoadCueEvaluator.nudge(for: input(recoveryValue: 80, rpe: 8.5)))
    }

    func testWarmupSetSkipped() {
        let warmup = SetCueSnapshot(setIndex: 0, weightKg: 40, reps: 10, rpe: 5, isWarmup: true)
        let cueInput = LiveLoadCueInput(
            recoveryScore: recoveryScore(value: 35),
            completedSet: warmup,
            targetRIR: 2,
            targetReps: 10
        )
        XCTAssertNil(LiveLoadCueEvaluator.nudge(for: cueInput))
    }

    func testSessionChipOnlyWhenLowRecovery() {
        XCTAssertEqual(
            LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: recoveryScore(value: 30)),
            "Low recovery day"
        )
        XCTAssertNil(LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: recoveryScore(value: 70)))
    }

    // MARK: - Recovery bands

    func testRecoveryBandThresholds() {
        XCTAssertEqual(RecoveryLoadBand.band(for: recoveryScore(value: 70)), .high)
        XCTAssertEqual(RecoveryLoadBand.band(for: recoveryScore(value: 69)), .moderate)
        XCTAssertEqual(RecoveryLoadBand.band(for: recoveryScore(value: 40)), .moderate)
        XCTAssertEqual(RecoveryLoadBand.band(for: recoveryScore(value: 39)), .low)
    }

    // MARK: - Composed cue order

    func testComposedCueOrderTierThenHRThenLoad() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sampledAt = now.addingTimeInterval(-5)
        let composed = LiveSetCueComposer.compose(
            tierMessage: "On plan.",
            loadNudge: "Recovery low. Hold weight.",
            heartRateBPM: 152,
            heartRateSampledAt: sampledAt,
            now: now
        )
        XCTAssertEqual(
            composed,
            "On plan.\nHeart rate still 152. Take the full rest.\nRecovery low. Hold weight."
        )
    }
}
