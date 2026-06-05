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
        reps: Int = 10,
        personalReadiness: PersonalReadinessProfile? = nil
    ) -> LiveLoadCueInput {
        LiveLoadCueInput(
            recoveryScore: recoveryScore(value: recoveryValue),
            personalReadiness: personalReadiness,
            completedSet: workingSet(rpe: rpe, reps: reps),
            targetRIR: targetRIR,
            targetReps: targetReps
        )
    }

    private func calibratedProfile(
        today: Double,
        p25: Double,
        median: Double,
        p75: Double,
        recoveryDebt: Double = 0,
        activeDisruptors: [ActiveDisruptorSummary] = []
    ) -> PersonalReadinessProfile {
        PersonalReadinessProfile(
            personalMedian: median,
            personalP25: p25,
            personalP75: p75,
            daysOfHistory: 30,
            isCalibrated: true,
            readinessDelta: today - median,
            readinessPercentile: 50,
            adjustedReadinessPercentile: 50,
            exertionDebtNormalized: nil,
            recoveryDebt: recoveryDebt,
            activeDisruptors: activeDisruptors,
            todayScore: today
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
            personalReadiness: nil,
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

    func testCalibratedScoreAtPersonalP75IsHighBand() {
        let profile = PersonalReadinessProfile(
            personalMedian: 50,
            personalP25: 44,
            personalP75: 55,
            daysOfHistory: 30,
            isCalibrated: true,
            readinessDelta: 6,
            readinessPercentile: 80,
            adjustedReadinessPercentile: 80,
            exertionDebtNormalized: nil,
            recoveryDebt: 0,
            activeDisruptors: [],
            todayScore: 56
        )
        let context = RecoveryBandContext(score: recoveryScore(value: 56), profile: profile)
        XCTAssertEqual(RecoveryLoadBand.band(for: context), .high)
    }

    func testCalibratedScoreBelowPersonalP25IsLowBand() {
        let profile = calibratedProfile(today: 42, p25: 45, median: 50, p75: 55)
        let context = RecoveryBandContext(score: recoveryScore(value: 42), profile: profile)
        XCTAssertEqual(RecoveryLoadBand.band(for: context), .low)
    }

    func testCalibratedChipUsesPersonalNormCopy() {
        let profile = calibratedProfile(today: 42, p25: 45, median: 50, p75: 55)
        let context = RecoveryBandContext(score: recoveryScore(value: 42), profile: profile)
        XCTAssertEqual(
            LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: context),
            "Recovery below your norm"
        )
    }

    func testCalibratedAlcoholChipPrefersRecoveringCopy() {
        let disruptor = ActiveDisruptorSummary(
            kind: .alcohol,
            source: .userTag,
            confidence: 1.0,
            daysSinceStart: 1,
            recoveryDebt: 0.7,
            userFacingLabel: "Alcohol (tagged)"
        )
        let profile = calibratedProfile(
            today: 42,
            p25: 45,
            median: 50,
            p75: 55,
            recoveryDebt: 0.7,
            activeDisruptors: [disruptor]
        )
        let context = RecoveryBandContext(score: recoveryScore(value: 42), profile: profile)
        XCTAssertEqual(
            LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: context),
            "Recovering from last night"
        )
    }

    func testCalibratedLowRecoveryHoldMessage() {
        let profile = calibratedProfile(today: 42, p25: 45, median: 50, p75: 55)
        let message = LiveLoadCueEvaluator.nudge(
            for: input(recoveryValue: 42, rpe: 5, personalReadiness: profile)
        )
        XCTAssertEqual(message, "Recovery below your norm. Hold weight.")
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
