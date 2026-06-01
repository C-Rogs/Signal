import Foundation
import os

enum Summarizer: Sendable {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder = JSONDecoder()

    static func summarize(
        metric: DailyMetric,
        workoutSummaries: [String] = [],
        calendar: Calendar = .current
    ) -> (summary: DailySummary, embeddingText: String) {
        let dayKey = Self.dayKey(for: metric.date, calendar: calendar)
        let workoutsSummary = Self.workoutsSummary(from: workoutSummaries)
        let summary = DailySummary(
            date: dayKey,
            hrvSDNN: metric.hrvSDNN_ms,
            restingHR: metric.restingHR,
            activeEnergy: metric.activeEnergy_kcal,
            sleepHours: metric.sleepHours,
            workoutsSummary: workoutsSummary,
            recoveryScore: nil
        )
        let text = Self.embeddingText(for: summary)
        Log.import.debug("summarized dayKey=\(dayKey, privacy: .public) textChars=\(text.count, privacy: .public)")
        return (summary, text)
    }

    static func encodeJSON(_ summary: DailySummary) throws -> Data {
        try jsonEncoder.encode(summary)
    }

    static func decodeJSON(_ data: Data) throws -> DailySummary {
        try jsonDecoder.decode(DailySummary.self, from: data)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        let month = calendar.component(.month, from: day)
        let dayOfMonth = calendar.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private static func workoutsSummary(from workoutSummaries: [String]) -> String? {
        let parts = workoutSummaries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ")
    }

    private static func embeddingText(for summary: DailySummary) -> String {
        var segments: [String] = ["Health day \(summary.date)."]
        if let hrvSDNN = summary.hrvSDNN {
            segments.append("HRV SDNN \(format(hrvSDNN, decimals: 1)) ms.")
        }
        if let restingHR = summary.restingHR {
            segments.append("Resting HR \(format(restingHR, decimals: 0)) bpm.")
        }
        if let activeEnergy = summary.activeEnergy {
            segments.append("Active energy \(format(activeEnergy, decimals: 0)) kcal.")
        }
        if let sleepHours = summary.sleepHours {
            segments.append("Sleep \(format(sleepHours, decimals: 2)) hours.")
        }
        if let workoutsSummary = summary.workoutsSummary {
            segments.append("Workouts: \(workoutsSummary).")
        }
        if let recoveryScore = summary.recoveryScore {
            segments.append("Recovery score \(format(recoveryScore, decimals: 0)).")
        }
        return segments.joined(separator: " ")
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
