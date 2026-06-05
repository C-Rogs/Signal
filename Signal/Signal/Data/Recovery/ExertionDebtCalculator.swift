import Foundation
import os

struct ExertionDebtSummary: Sendable, Equatable {
    let rolling7dSum: Double
    let exertionDebtNormalized: Double
    let yesterdayScore: Double?
    let personalP90Daily: Double?
    let personalP90Rolling7d: Double?
    let todayExertion: ExertionScore?
    let isCalibrated: Bool
}

enum ExertionDebtCalculator {
    static func summary(
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        referenceDay: Date,
        calendar: Calendar
    ) -> ExertionDebtSummary {
        let end = calendar.startOfDay(for: referenceDay)
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.debtHistoryDays - 1),
            to: end
        ) else {
            return emptySummary(isCalibrated: baselines.isCalibrated)
        }

        var dailyScores: [(date: Date, score: Double)] = []
        var day = historyStart
        while day <= end {
            if let exertion = ExertionScoreCalculator.score(
                for: day,
                metrics: metrics,
                sessions: sessions,
                baselines: baselines,
                calendar: calendar
            ) {
                dailyScores.append((date: day, score: exertion.value))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let rollingSums = rolling7dSums(from: dailyScores, referenceDay: end, calendar: calendar)
        let todayRolling = rollingSums.last?.sum ?? 0
        let p90Rolling = percentile(sorted: rollingSums.map(\.sum), p: 0.9)
        let normalized: Double
        if let p90Rolling, p90Rolling > 0 {
            normalized = min(1, todayRolling / p90Rolling)
        } else {
            normalized = 0
        }

        let yesterday: Double?
        if let prior = calendar.date(byAdding: .day, value: -1, to: end) {
            yesterday = dailyScores.first { calendar.isDate($0.date, inSameDayAs: prior) }?.score
        } else {
            yesterday = nil
        }

        let dailyValues = dailyScores.map(\.score)
        let p90Daily = percentile(sorted: dailyValues.sorted(), p: 0.9)

        let todayExertion = ExertionScoreCalculator.score(
            for: end,
            metrics: metrics,
            sessions: sessions,
            baselines: baselines,
            calendar: calendar
        )

        Log.recovery.info(
            "exertion debt=\(normalized, privacy: .public) rolling7d=\(todayRolling, privacy: .public) p90=\(p90Rolling ?? -1, privacy: .public)"
        )

        return ExertionDebtSummary(
            rolling7dSum: todayRolling,
            exertionDebtNormalized: normalized,
            yesterdayScore: yesterday,
            personalP90Daily: p90Daily,
            personalP90Rolling7d: p90Rolling,
            todayExertion: todayExertion,
            isCalibrated: baselines.isCalibrated
        )
    }

    static func rolling7dSum(
        on referenceDay: Date,
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        calendar: Calendar
    ) -> Double {
        let end = calendar.startOfDay(for: referenceDay)
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )
        guard let windowStart = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.rollingDebtWindowDays - 1),
            to: end
        ) else { return 0 }

        var sum = 0.0
        var day = windowStart
        while day <= end {
            if let score = ExertionScoreCalculator.score(
                for: day,
                metrics: metrics,
                sessions: sessions,
                baselines: baselines,
                calendar: calendar
            ) {
                sum += score.value
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return sum
    }

    private static func rolling7dSums(
        from dailyScores: [(date: Date, score: Double)],
        referenceDay: Date,
        calendar: Calendar
    ) -> [(date: Date, sum: Double)] {
        let scoresByDay = Dictionary(uniqueKeysWithValues: dailyScores.map {
            (calendar.startOfDay(for: $0.date), $0.score)
        })
        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.debtHistoryDays - 1),
            to: referenceDay
        ) else { return [] }

        var results: [(date: Date, sum: Double)] = []
        var day = historyStart
        while day <= referenceDay {
            guard let windowStart = calendar.date(
                byAdding: .day,
                value: -(ExertionHeuristics.rollingDebtWindowDays - 1),
                to: day
            ) else { break }

            var sum = 0.0
            var windowDay = windowStart
            while windowDay <= day {
                sum += scoresByDay[calendar.startOfDay(for: windowDay)] ?? 0
                guard let next = calendar.date(byAdding: .day, value: 1, to: windowDay) else { break }
                windowDay = next
            }
            results.append((date: day, sum: sum))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    private static func percentile(sorted: [Double], p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        guard sorted.count > 1 else { return sorted[0] }
        let position = p * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func emptySummary(isCalibrated: Bool) -> ExertionDebtSummary {
        ExertionDebtSummary(
            rolling7dSum: 0,
            exertionDebtNormalized: 0,
            yesterdayScore: nil,
            personalP90Daily: nil,
            personalP90Rolling7d: nil,
            todayExertion: nil,
            isCalibrated: isCalibrated
        )
    }
}
