import Foundation

struct DailyBriefingContent: Sendable, Equatable {
    let title: String
    let body: String
}

struct DailyBriefingInsightLine: Sendable, Equatable {
    let bodyText: String
    let severity: InsightSeverity
}

enum DailyBriefingComposer {
    static let notificationTitle = "Morning briefing"

    static func compose(
        recoveryScore: RecoveryScore,
        personalReadiness: PersonalReadinessProfile?,
        insight: DailyBriefingInsightLine?,
        flags: ReadinessFlagsAssessment?,
        deloadActive: Bool = false
    ) -> DailyBriefingContent {
        var parts: [String] = [recoverySummary(for: recoveryScore, personalReadiness: personalReadiness)]

        if let disruptorLine = disruptorBriefingLine(personalReadiness: personalReadiness) {
            parts.append(disruptorLine)
        }

        if deloadActive, let deloadLine = deloadBriefingLine() {
            parts.append(deloadLine)
        }

        if let flags, flags.aggregateSeverity >= .caution {
            parts.append(flags.headline)
        } else if let flags {
            parts.append(flags.detail)
        } else if let insight {
            parts.append(insight.bodyText)
        }

        let body = parts.joined(separator: " ")
        return DailyBriefingContent(title: notificationTitle, body: body)
    }

    static func recoverySummary(
        for score: RecoveryScore,
        personalReadiness: PersonalReadinessProfile?
    ) -> String {
        let band = recoveryBandPhrase(for: score, personalReadiness: personalReadiness)
        let scoreInt = Int(score.value.rounded())
        if let profile = personalReadiness, profile.isCalibrated {
            let delta = Int(profile.readinessDelta.rounded())
            let deltaText: String
            if delta == 0 {
                deltaText = "at your norm"
            } else {
                let sign = delta > 0 ? "+" : ""
                deltaText = "\(sign)\(delta) vs your norm"
            }
            return "Recovery looks \(band) (\(scoreInt)/100, \(deltaText))."
        }
        return "Recovery looks \(band) (\(scoreInt)/100)."
    }

    static func recoveryBandPhrase(
        for score: RecoveryScore,
        personalReadiness: PersonalReadinessProfile?
    ) -> String {
        if let profile = personalReadiness, profile.isCalibrated {
            if score.value >= profile.personalP75 { return "above your norm" }
            if score.value >= profile.personalP25 { return "steady for you" }
            return "below your norm"
        }
        switch score.value {
        case 70...:
            return "strong"
        case 45..<70:
            return "steady"
        default:
            return "strained"
        }
    }

    private static func disruptorBriefingLine(personalReadiness: PersonalReadinessProfile?) -> String? {
        guard let profile = personalReadiness else { return nil }
        guard let top = profile.activeDisruptors.first else { return nil }

        switch top.kind {
        case .alcohol where top.source == .userTag:
            return "You tagged alcohol last night. Recovery may take a day or two to return to your norm."
        case .alcohol where top.confidence >= RecoveryDisruptorHeuristics.alcoholHighConfidenceThreshold:
            return "Recovery looks disrupted after last night."
        case .alcohol:
            return top.userFacingLabel
        case .trainingLoad:
            if let debt = profile.exertionDebtNormalized,
               debt >= ExertionHeuristics.exertionDebtHighThreshold
            {
                return "Training load and strain debt are elevated. Consider easing intensity today."
            }
            return "Training load is elevated. Consider easing intensity today."
        case .sleepDebt:
            return "Sleep debt is active. Prioritise rest before adding load."
        case .illnessLike:
            return "Several recovery signals look strained today."
        case .unknown:
            return top.userFacingLabel
        }
    }

    static func deloadBriefingLine() -> String? {
        "Load is above your recent norm. A deload session with fewer working sets may help."
    }

    static func selectPriorityInsight(from insights: [DailyBriefingInsightLine]) -> DailyBriefingInsightLine? {
        insights.max { lhs, rhs in
            lhs.severity.sortRank < rhs.severity.sortRank
        }
    }
}

private extension InsightSeverity {
    var sortRank: Int {
        switch self {
        case .alert: 2
        case .warning: 1
        case .info: 0
        }
    }
}
