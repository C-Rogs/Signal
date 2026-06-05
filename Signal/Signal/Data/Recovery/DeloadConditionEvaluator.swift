import Foundation

enum DeloadConditionEvaluator {
    static func isDeloadDay(
        acwr: ACWRResult?,
        exertionDebtNormalized: Double
    ) -> Bool {
        guard let acwr else { return false }
        switch acwr.zone {
        case .overreach:
            return true
        case .caution:
            return exertionDebtNormalized >= ExertionHeuristics.exertionDebtHighThreshold
        case .belowOptimal, .optimal:
            return false
        }
    }

    static func deloadSuggested(
        acwr: ACWRResult?,
        exertionDebt: ExertionDebtSummary,
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        let today = isDeloadDay(acwr: acwr, exertionDebtNormalized: exertionDebt.exertionDebtNormalized)
        guard today else { return false }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: referenceDay)) else {
            return false
        }

        let yesterdayACWR = Self.acwr(on: yesterday, sessions: sessions, calendar: calendar)
        let yesterdayDebt = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: sessions,
            referenceDay: yesterday,
            calendar: calendar
        )
        return isDeloadDay(
            acwr: yesterdayACWR,
            exertionDebtNormalized: yesterdayDebt.exertionDebtNormalized
        )
    }

    static func acwr(
        on day: Date,
        sessions: [WorkoutDaySession],
        calendar: Calendar
    ) -> ACWRResult? {
        let refDay = calendar.startOfDay(for: day)
        guard let chronicStart = calendar.date(byAdding: .day, value: -27, to: refDay) else {
            return nil
        }

        var loadsByDay: [Date: Int] = [:]
        for session in sessions {
            let sessionDay = calendar.startOfDay(for: session.date)
            guard sessionDay >= chronicStart, sessionDay <= refDay else { continue }
            loadsByDay[sessionDay, default: 0] += session.workingSetCount
        }

        let dailyLoads = loadsByDay.map { (date: $0.key, totalSets: $0.value) }
        return ACWRCalculator.compute(dailyLoads: dailyLoads, referenceDate: refDay, calendar: calendar)
    }
}
