import Foundation

/// Readiness and RPE load prescription nudges during Train (suggest only; never mutates logged weight).
enum LiveLoadAutoregulation {
    // Recovery bands (align with WatchPayload and device gate table).
    static let recoveryHighThreshold = 70.0
    static let recoveryLowThreshold = 40.0
    static let calibratedHighPercentile = 60.0
    static let calibratedRecoveryDebtLowThreshold = 0.5

    // RPE tiers (align with CueEngine).
    static let easyRPEMax = 6.0
    static let grindRPEMin = 9.0

    static let suggestedLoadIncrementKg = 2.5
}

enum RecoveryLoadBand: String, Sendable, Equatable {
    case high
    case moderate
    case low

    static func band(for score: RecoveryScore) -> RecoveryLoadBand {
        band(for: RecoveryBandContext(score: score, profile: nil))
    }

    static func band(for context: RecoveryBandContext) -> RecoveryLoadBand {
        guard let profile = context.profile, profile.isCalibrated else {
            return bandAbsolute(for: context.score)
        }

        let score = context.score.value
        let effectivePercentile = profile.exertionDebtNormalized != nil
            ? profile.adjustedReadinessPercentile
            : profile.readinessPercentile
        if score >= profile.personalP75
            || (profile.recoveryDebt <= LiveLoadAutoregulation.calibratedRecoveryDebtLowThreshold
                && effectivePercentile >= LiveLoadAutoregulation.calibratedHighPercentile)
        {
            return .high
        }

        if score <= profile.personalP25
            || profile.recoveryDebt > LiveLoadAutoregulation.calibratedRecoveryDebtLowThreshold
            || score < profile.personalP25
            || (profile.exertionDebtNormalized != nil
                && effectivePercentile < LiveLoadAutoregulation.calibratedHighPercentile)
        {
            return .low
        }

        return .moderate
    }

    static func bandAbsolute(for score: RecoveryScore) -> RecoveryLoadBand {
        switch score.value {
        case LiveLoadAutoregulation.recoveryHighThreshold...:
            return .high
        case LiveLoadAutoregulation.recoveryLowThreshold..<LiveLoadAutoregulation.recoveryHighThreshold:
            return .moderate
        default:
            return .low
        }
    }
}

struct RecoveryBandContext: Sendable, Equatable {
    let score: RecoveryScore
    let profile: PersonalReadinessProfile?
}

struct LiveLoadCueInput: Sendable, Equatable {
    let recoveryScore: RecoveryScore
    let personalReadiness: PersonalReadinessProfile?
    let completedSet: SetCueSnapshot
    let targetRIR: Int
    let targetReps: Int?
}

enum LiveLoadCueEvaluator {
    static func nudge(for input: LiveLoadCueInput) -> String? {
        guard !input.completedSet.isWarmup else { return nil }
        guard let rpe = input.completedSet.rpe else { return nil }

        if CueEngine.isHighRPE(rpe) {
            return grindHoldMessage
        }

        let context = RecoveryBandContext(score: input.recoveryScore, profile: input.personalReadiness)
        let band = RecoveryLoadBand.band(for: context)

        switch band {
        case .low:
            return lowRecoveryHoldMessage(calibrated: input.personalReadiness?.isCalibrated == true)
        case .high:
            if isEasyAtTargetRIR(rpe: rpe, targetRIR: input.targetRIR, targetReps: input.targetReps, reps: input.completedSet.reps) {
                return easyAddLoadMessage
            }
            return nil
        case .moderate:
            return nil
        }
    }

    static func sessionRecoveryChipTitle(for context: RecoveryBandContext) -> String? {
        let band = RecoveryLoadBand.band(for: context)
        guard band == .low else { return nil }

        if let profile = context.profile, profile.isCalibrated {
            if PersonalReadinessCalculator.hasActiveAlcoholDisruptor(in: profile) {
                return "Recovering from last night"
            }
            return "Recovery below your norm"
        }

        return "Low recovery day"
    }

    static func sessionRecoveryChipTitle(for score: RecoveryScore) -> String? {
        sessionRecoveryChipTitle(for: RecoveryBandContext(score: score, profile: nil))
    }

    static func effectiveRIR(from rpe: Double) -> Double {
        max(0, 10 - rpe)
    }

    static func isEasyAtTargetRIR(
        rpe: Double,
        targetRIR: Int,
        targetReps: Int?,
        reps: Int?
    ) -> Bool {
        guard rpe <= LiveLoadAutoregulation.easyRPEMax else { return false }
        guard effectiveRIR(from: rpe) >= Double(targetRIR) else { return false }
        if let targetReps, let reps {
            return reps >= targetReps
        }
        return true
    }

    private static func lowRecoveryHoldMessage(calibrated: Bool) -> String {
        calibrated ? "Recovery below your norm. Hold weight." : "Recovery low. Hold weight."
    }

    private static let easyAddLoadMessage =
        "Easy set at target RIR. Add \(LiveLoadAutoregulation.suggestedLoadIncrementKg) kg next set."
    private static let grindHoldMessage = "RPE 9+. Stay at this weight for remaining sets."
}
