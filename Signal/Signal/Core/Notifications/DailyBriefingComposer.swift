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
        insight: DailyBriefingInsightLine?,
        flags: ReadinessFlagsAssessment?
    ) -> DailyBriefingContent {
        var parts: [String] = [recoverySummary(for: recoveryScore)]

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

    static func recoverySummary(for score: RecoveryScore) -> String {
        let band = recoveryBandPhrase(for: score)
        let scoreInt = Int(score.value.rounded())
        return "Recovery looks \(band) (\(scoreInt)/100)."
    }

    static func recoveryBandPhrase(for score: RecoveryScore) -> String {
        switch score.value {
        case 70...:
            return "strong"
        case 45..<70:
            return "steady"
        default:
            return "strained"
        }
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
