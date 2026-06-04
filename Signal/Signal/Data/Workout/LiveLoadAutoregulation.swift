import Foundation

/// Readiness and RPE load prescription nudges during Train (suggest only; never mutates logged weight).
enum LiveLoadAutoregulation {
    // Recovery bands (align with WatchPayload and device gate table).
    static let recoveryHighThreshold = 70.0
    static let recoveryLowThreshold = 40.0

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

struct LiveLoadCueInput: Sendable, Equatable {
    let recoveryScore: RecoveryScore
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

        let band = RecoveryLoadBand.band(for: input.recoveryScore)

        switch band {
        case .low:
            return lowRecoveryHoldMessage
        case .high:
            if isEasyAtTargetRIR(rpe: rpe, targetRIR: input.targetRIR, targetReps: input.targetReps, reps: input.completedSet.reps) {
                return easyAddLoadMessage
            }
            return nil
        case .moderate:
            return nil
        }
    }

    static func sessionRecoveryChipTitle(for score: RecoveryScore) -> String? {
        guard RecoveryLoadBand.band(for: score) == .low else { return nil }
        return "Low recovery day"
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

    private static let lowRecoveryHoldMessage = "Recovery low. Hold weight."
    private static let easyAddLoadMessage =
        "Easy set at target RIR. Add \(LiveLoadAutoregulation.suggestedLoadIncrementKg) kg next set."
    private static let grindHoldMessage = "RPE 9+. Stay at this weight for remaining sets."
}
