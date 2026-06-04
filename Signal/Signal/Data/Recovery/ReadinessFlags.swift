import Foundation
import os

enum FlagSeverity: String, Sendable, Equatable, Comparable {
    case notice
    case caution
    case elevated

    private var rank: Int {
        switch self {
        case .notice: 0
        case .caution: 1
        case .elevated: 2
        }
    }

    static func < (lhs: FlagSeverity, rhs: FlagSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum ReadinessSignalKind: String, Sendable, Equatable, CaseIterable {
    case restingHRElevated
    case hrvBelowBand
    case wristTemperatureElevated
}

struct ReadinessSignal: Sendable, Equatable {
    let kind: ReadinessSignalKind
    let severity: FlagSeverity
    let coachingLine: String
}

struct ReadinessFlagsAssessment: Sendable, Equatable {
    let signals: [ReadinessSignal]
    let aggregateSeverity: FlagSeverity
    let headline: String
    let detail: String
}

struct ReadinessFlagInput: Sendable, Equatable {
    let metrics: [DailyMetricSnapshot]
    let recoveryScore: RecoveryScore
    let referenceDay: Date
    let calendar: Calendar
}

enum ReadinessFlagEvaluator {
    static let restingHRElevatedDeltaBpm = 3.0
    static let wristTemperatureElevatedDeltaC = 0.5
    static let minimumSleepHoursForWristTemperatureFlag = 1.0

    static func evaluate(_ input: ReadinessFlagInput) -> ReadinessFlagsAssessment? {
        var signals: [ReadinessSignal] = []

        if isRestingHRElevated(score: input.recoveryScore) {
            signals.append(
                ReadinessSignal(
                    kind: .restingHRElevated,
                    severity: .notice,
                    coachingLine: "Resting heart rate is above your recent average."
                )
            )
        }

        if isHRVBelowBand(score: input.recoveryScore) {
            signals.append(
                ReadinessSignal(
                    kind: .hrvBelowBand,
                    severity: .notice,
                    coachingLine: "Heart rate variability is below your normal band."
                )
            )
        }

        if isWristTemperatureElevated(metrics: input.metrics, input: input) {
            signals.append(
                ReadinessSignal(
                    kind: .wristTemperatureElevated,
                    severity: .notice,
                    coachingLine: "Sleeping wrist temperature is elevated versus your baseline."
                )
            )
        }

        guard !signals.isEmpty else { return nil }

        let aggregate = aggregateSeverity(signalCount: signals.count)
        let headline = headline(for: aggregate)
        let detail = detail(for: signals, aggregate: aggregate)

        Log.recovery.info(
            "readiness flags count=\(signals.count, privacy: .public) severity=\(aggregate.rawValue, privacy: .public)"
        )

        return ReadinessFlagsAssessment(
            signals: signals,
            aggregateSeverity: aggregate,
            headline: headline,
            detail: detail
        )
    }

    static func isRestingHRElevated(score: RecoveryScore) -> Bool {
        guard let delta = score.rhrDelta else { return false }
        return delta >= restingHRElevatedDeltaBpm
    }

    static func isHRVBelowBand(score: RecoveryScore) -> Bool {
        score.hrvClassification == .belowLowerBand
            && score.hrvAnalysis != nil
    }

    static func isWristTemperatureElevated(
        metrics: [DailyMetricSnapshot],
        input: ReadinessFlagInput
    ) -> Bool {
        let end = input.calendar.startOfDay(for: input.referenceDay)
        guard let today = metrics.first(where: { input.calendar.isDate($0.date, inSameDayAs: end) }),
              let sleepHours = today.sleepHours,
              sleepHours >= minimumSleepHoursForWristTemperatureFlag,
              let delta = today.wristTemperatureDeltaC
        else { return false }
        return delta >= wristTemperatureElevatedDeltaC
    }

    static func aggregateSeverity(signalCount: Int) -> FlagSeverity {
        switch signalCount {
        case 3...: .elevated
        case 2: .caution
        default: .notice
        }
    }

    static func headline(for severity: FlagSeverity) -> String {
        switch severity {
        case .notice:
            return "Recovery looks a little off today"
        case .caution:
            return "Your body may need extra rest"
        case .elevated:
            return "Several recovery signals are strained"
        }
    }

    static func detail(for signals: [ReadinessSignal], aggregate: FlagSeverity) -> String {
        let lines = signals.map(\.coachingLine)
        let joined = lines.joined(separator: " ")
        switch aggregate {
        case .notice:
            return "\(joined) Keep training moderate and prioritise sleep."
        case .caution:
            return "\(joined) Consider an easier session or a rest day."
        case .elevated:
            return "\(joined) Ease intensity and recovery habits today. If you feel unwell, check in with a clinician."
        }
    }
}
