import Foundation

private enum CoachContextLimits {
    static let maxUserSummaryChars = 400
    static let maxActiveInsightsTotalChars = 800
    static let maxDerivedMetricsSummaryChars = 800
    static let maxRAGSummariesTotalChars = 4000
    static let maxRecentWorkoutsTotalChars = 1200
    static let maxCalendarSummaryChars = 1200
    static let assembledPromptMaxChars = 7200
    static let maxInputChars = 8000
}

struct CoachContext: Sendable, Equatable {
    static let assembledPromptMaxChars = CoachContextLimits.assembledPromptMaxChars

    var userSummary: String
    var activeInsights: [String]
    var derivedMetricsSummary: String
    var ragSummaries: [String]
    var recentWorkouts: [String]
    var calendarSummary: String

    init(
        userSummary: String,
        activeInsights: [String],
        derivedMetricsSummary: String,
        ragSummaries: [String],
        recentWorkouts: [String],
        calendarSummary: String = ""
    ) {
        self.userSummary = Self.clamped(userSummary, max: CoachContextLimits.maxUserSummaryChars)
        self.activeInsights = Self.clampedLines(activeInsights, maxTotal: CoachContextLimits.maxActiveInsightsTotalChars)
        self.derivedMetricsSummary = Self.clamped(derivedMetricsSummary, max: CoachContextLimits.maxDerivedMetricsSummaryChars)
        self.ragSummaries = Self.clampedLines(ragSummaries, maxTotal: CoachContextLimits.maxRAGSummariesTotalChars)
        self.recentWorkouts = Self.clampedLines(recentWorkouts, maxTotal: CoachContextLimits.maxRecentWorkoutsTotalChars)
        self.calendarSummary = Self.clamped(calendarSummary, max: CoachContextLimits.maxCalendarSummaryChars)
    }

    func assembledPrompt(query: String) -> String {
        var sections: [String] = []

        if !userSummary.isEmpty {
            sections.append("## User\n\(userSummary)")
        }
        if !activeInsights.isEmpty {
            sections.append("## Active insights\n\(activeInsights.joined(separator: "\n"))")
        }
        if !derivedMetricsSummary.isEmpty {
            sections.append("## Metrics\n\(derivedMetricsSummary)")
        }
        if !ragSummaries.isEmpty {
            sections.append("## History (RAG)\n\(ragSummaries.joined(separator: "\n\n"))")
        }
        if !recentWorkouts.isEmpty {
            sections.append("## Recent workouts\n\(recentWorkouts.joined(separator: "\n"))")
        }
        if !calendarSummary.isEmpty {
            sections.append("## Schedule\n\(calendarSummary)")
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append("## Question\n\(trimmedQuery)")

        return sections.joined(separator: "\n\n")
    }

    mutating func truncatingToFitBudget(
        maxChars: Int = CoachContextLimits.assembledPromptMaxChars,
        sampleQuery: String = ""
    ) {
        let probe = sampleQuery.isEmpty ? "?" : sampleQuery
        while assembledPrompt(query: probe).count > maxChars {
            if !ragSummaries.isEmpty {
                ragSummaries.removeFirst()
                continue
            }
            if recentWorkouts.count > 1 {
                recentWorkouts = Array(recentWorkouts.prefix(1))
                continue
            }
            if derivedMetricsSummary.count > 120 {
                let keep = max(80, derivedMetricsSummary.count / 2)
                derivedMetricsSummary = String(derivedMetricsSummary.prefix(keep))
                continue
            }
            break
        }
    }

    mutating func dropOldestHalfOfRAGSummaries() {
        guard !ragSummaries.isEmpty else { return }
        let removeCount = max(1, ragSummaries.count / 2)
        ragSummaries.removeFirst(removeCount)
    }

    mutating func prepareForModelInput(query: String) {
        truncatingToFitBudget(maxChars: CoachContextLimits.assembledPromptMaxChars, sampleQuery: query)
        while assembledPrompt(query: query).count > CoachContextLimits.maxInputChars {
            if !ragSummaries.isEmpty {
                ragSummaries.removeFirst()
                continue
            }
            if recentWorkouts.count > 1 {
                recentWorkouts = Array(recentWorkouts.prefix(1))
                continue
            }
            if derivedMetricsSummary.count > 80 {
                derivedMetricsSummary = String(derivedMetricsSummary.prefix(derivedMetricsSummary.count / 2))
                continue
            }
            break
        }
    }

    private static func clamped(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max))
    }

    private static func clampedLines(_ lines: [String], maxTotal: Int) -> [String] {
        var result: [String] = []
        var used = 0
        for line in lines {
            let addition = line.count + (result.isEmpty ? 0 : 1)
            guard used + addition <= maxTotal else { break }
            result.append(line)
            used += addition
        }
        return result
    }
}
