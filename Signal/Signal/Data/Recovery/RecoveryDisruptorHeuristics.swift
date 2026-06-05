import Foundation

enum RecoveryDisruptorHeuristics {
    static let alcoholProxySleepHoursMax = 6.5
    static let alcoholProxyRHRElevatedBpm = 3.0
    static let alcoholProxyBaseConfidence = 0.6
    static let alcoholProxyWristTempBonus = 0.15
    static let alcoholHighConfidenceThreshold = 0.75
    static let trainingLoadACWRThreshold = 1.5
    static let exertionDebtHighThreshold = ExertionHeuristics.exertionDebtHighThreshold
    static let trainingLoadInferenceBaseConfidence = 0.5
    static let sleepDebtConsecutiveDays = 2
    static let sleepDebtHoursMax = 6.5
    static let illnessLikeMinimumSignals = 2
    static let activeEpisodeMaxAgeDays = 7
    static let calibrationMinimumDays = 21
    static let historyLookbackDays = 60

    static let defaultHalfLifeDays: [RecoveryDisruptorKind: Double] = [
        .alcohol: 2,
        .trainingLoad: 1,
        .sleepDebt: 1,
        .illnessLike: 3,
        .unknown: 2,
    ]

    static let learnedHalfLifeMinimumDays = 1.0
    static let learnedHalfLifeMaximumDays = 5.0
    static let learnedAlcoholMinimumEpisodes = 3

    static func inferredDedupeKey(kind: RecoveryDisruptorKind, day: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: day)
        return "inferred.\(kind.rawValue).\(Int(start.timeIntervalSince1970))"
    }

    static func userTagDedupeKey(kind: RecoveryDisruptorKind, startDay: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: startDay)
        return "userTag.\(kind.rawValue).\(Int(start.timeIntervalSince1970))"
    }
}
