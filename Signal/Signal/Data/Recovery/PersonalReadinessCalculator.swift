import Foundation
import os

struct ActiveDisruptorSummary: Sendable, Equatable {
    let kind: RecoveryDisruptorKind
    let source: RecoveryDisruptorSource
    let confidence: Double
    let daysSinceStart: Int
    let recoveryDebt: Double
    let userFacingLabel: String
}

struct PersonalReadinessProfile: Sendable, Equatable {
    let personalMedian: Double
    let personalP25: Double
    let personalP75: Double
    let daysOfHistory: Int
    let isCalibrated: Bool
    let readinessDelta: Double
    let readinessPercentile: Double
    let adjustedReadinessPercentile: Double
    let exertionDebtNormalized: Double?
    let recoveryDebt: Double
    let activeDisruptors: [ActiveDisruptorSummary]
    let todayScore: Double
}

enum PersonalReadinessCalculator {
    static func compute(
        metrics: [DailyMetricSnapshot],
        todayScore: RecoveryScore,
        activeEpisodes: [RecoveryDisruptorEpisodeSnapshot],
        referenceDay: Date,
        calendar: Calendar,
        exertionDebtNormalized: Double? = nil
    ) -> PersonalReadinessProfile {
        let end = calendar.startOfDay(for: referenceDay)
        let historicalScores = historicalScoreValues(
            metrics: metrics,
            referenceDay: end,
            calendar: calendar
        )
        let daysOfHistory = historicalScores.count
        let isCalibrated = daysOfHistory >= RecoveryDisruptorHeuristics.calibrationMinimumDays

        let sorted = historicalScores.map(\.value).sorted()
        let personalMedian = percentile(sorted, p: 0.5) ?? todayScore.value
        let personalP25 = percentile(sorted, p: 0.25) ?? personalMedian
        let personalP75 = percentile(sorted, p: 0.75) ?? personalMedian
        let readinessDelta = todayScore.value - personalMedian
        let readinessPercentile = percentileRank(
            value: todayScore.value,
            in: sorted
        )
        let adjustedReadinessPercentile = adjustedPercentile(
            readinessPercentile: readinessPercentile,
            exertionDebtNormalized: exertionDebtNormalized
        )

        let learnedAlcoholHalfLife = learnedHalfLife(
            for: .alcohol,
            episodes: activeEpisodes,
            metrics: metrics,
            personalMedian: personalMedian,
            calendar: calendar
        )

        var activeDisruptors: [ActiveDisruptorSummary] = []
        var maxDebt = 0.0

        for episode in activeEpisodes where isEpisodeActive(episode, referenceDay: end, calendar: calendar) {
            let daysSinceStart = daysBetween(
                from: episode.startDay,
                to: end,
                calendar: calendar
            )
            let halfLife = halfLifeDays(
                for: episode.kind,
                learnedAlcoholHalfLife: learnedAlcoholHalfLife
            )
            let debt = recoveryDebt(daysSinceStart: daysSinceStart, halfLifeDays: halfLife)
            maxDebt = max(maxDebt, debt)

            activeDisruptors.append(
                ActiveDisruptorSummary(
                    kind: episode.kind,
                    source: episode.source,
                    confidence: episode.confidence,
                    daysSinceStart: daysSinceStart,
                    recoveryDebt: debt,
                    userFacingLabel: userFacingLabel(for: episode)
                )
            )
        }

        activeDisruptors.sort { lhs, rhs in
            lhs.recoveryDebt > rhs.recoveryDebt
        }

        Log.recovery.info(
            "personal readiness calibrated=\(isCalibrated, privacy: .public) median=\(personalMedian, privacy: .public) percentile=\(readinessPercentile, privacy: .public) adjusted=\(adjustedReadinessPercentile, privacy: .public) exertionDebt=\(exertionDebtNormalized ?? -1, privacy: .public) debt=\(maxDebt, privacy: .public) disruptors=\(activeDisruptors.count, privacy: .public)"
        )

        return PersonalReadinessProfile(
            personalMedian: personalMedian,
            personalP25: personalP25,
            personalP75: personalP75,
            daysOfHistory: daysOfHistory,
            isCalibrated: isCalibrated,
            readinessDelta: readinessDelta,
            readinessPercentile: readinessPercentile,
            adjustedReadinessPercentile: adjustedReadinessPercentile,
            exertionDebtNormalized: exertionDebtNormalized,
            recoveryDebt: maxDebt,
            activeDisruptors: activeDisruptors,
            todayScore: todayScore.value
        )
    }

    static func adjustedPercentile(
        readinessPercentile: Double,
        exertionDebtNormalized: Double?
    ) -> Double {
        guard let exertionDebtNormalized else { return readinessPercentile }
        let penalty = exertionDebtNormalized * ExertionHeuristics.readinessDebtPenaltyMax
        return min(100, max(0, readinessPercentile - penalty))
    }

    static func learnedHalfLife(
        for kind: RecoveryDisruptorKind,
        episodes: [RecoveryDisruptorEpisodeSnapshot],
        metrics: [DailyMetricSnapshot],
        personalMedian: Double,
        calendar: Calendar
    ) -> Double? {
        guard kind == .alcohol else { return nil }

        let tagged = episodes.filter {
            $0.kind == .alcohol && $0.source == .userTag
        }
        guard tagged.count >= RecoveryDisruptorHeuristics.learnedAlcoholMinimumEpisodes else {
            return nil
        }

        var recoveryDurations: [Int] = []
        for episode in tagged {
            if let days = daysUntilScoreReturnsToMedian(
                from: episode.startDay,
                personalMedian: personalMedian,
                metrics: metrics,
                calendar: calendar
            ) {
                recoveryDurations.append(days)
            }
        }

        guard !recoveryDurations.isEmpty else { return nil }
        let sorted = recoveryDurations.sorted()
        let median = Double(sorted[sorted.count / 2])
        return min(
            RecoveryDisruptorHeuristics.learnedHalfLifeMaximumDays,
            max(RecoveryDisruptorHeuristics.learnedHalfLifeMinimumDays, median)
        )
    }

    static func halfLifeDays(
        for kind: RecoveryDisruptorKind,
        learnedAlcoholHalfLife: Double?
    ) -> Double {
        if kind == .alcohol, let learnedAlcoholHalfLife {
            return learnedAlcoholHalfLife
        }
        return RecoveryDisruptorHeuristics.defaultHalfLifeDays[kind] ?? 2
    }

    static func recoveryDebt(daysSinceStart: Int, halfLifeDays: Double) -> Double {
        guard halfLifeDays > 0 else { return 0 }
        return pow(0.5, Double(daysSinceStart) / halfLifeDays)
    }

    static func userFacingLabel(for episode: RecoveryDisruptorEpisodeSnapshot) -> String {
        switch episode.kind {
        case .alcohol:
            if episode.source == .userTag {
                return "Alcohol (tagged)"
            }
            if episode.confidence >= RecoveryDisruptorHeuristics.alcoholHighConfidenceThreshold {
                return "Alcohol (likely)"
            }
            return "Recovery looks disrupted (poor sleep + elevated RHR)"
        case .trainingLoad:
            return "High training load"
        case .sleepDebt:
            return "Sleep debt"
        case .illnessLike:
            return "Illness-like recovery signals"
        case .unknown:
            return "Recovery disrupted"
        }
    }

    static func hasActiveAlcoholDisruptor(in profile: PersonalReadinessProfile) -> Bool {
        profile.activeDisruptors.contains { summary in
            guard summary.kind == .alcohol else { return false }
            if summary.source == .userTag { return true }
            return summary.confidence >= RecoveryDisruptorHeuristics.alcoholHighConfidenceThreshold
        }
    }

    private static func historicalScoreValues(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> [(date: Date, value: Double)] {
        guard RecoveryDisruptorHeuristics.historyLookbackDays > 0,
              let start = calendar.date(
                byAdding: .day,
                value: -(RecoveryDisruptorHeuristics.historyLookbackDays - 1),
                to: referenceDay
              )
        else { return [] }

        let metricsByDay = Dictionary(
            uniqueKeysWithValues: metrics.map {
                (calendar.startOfDay(for: $0.date), $0)
            }
        )

        var results: [(date: Date, value: Double)] = []
        var day = start
        while day <= referenceDay {
            guard metricsByDay[day] != nil else {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                continue
            }
            let score = RecoveryScoreCalculator.compute(
                metrics: metrics,
                referenceDay: day,
                calendar: calendar
            )
            results.append((date: day, value: score.value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    private static func daysUntilScoreReturnsToMedian(
        from startDay: Date,
        personalMedian: Double,
        metrics: [DailyMetricSnapshot],
        calendar: Calendar
    ) -> Int? {
        let start = calendar.startOfDay(for: startDay)
        for offset in 0..<RecoveryDisruptorHeuristics.historyLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let score = RecoveryScoreCalculator.compute(
                metrics: metrics,
                referenceDay: day,
                calendar: calendar
            )
            if score.value >= personalMedian {
                return offset
            }
        }
        return nil
    }

    private static func isEpisodeActive(
        _ episode: RecoveryDisruptorEpisodeSnapshot,
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: episode.startDay)
        guard start <= referenceDay else { return false }
        if let endDay = episode.endDay {
            return calendar.startOfDay(for: endDay) >= referenceDay
        }
        let daysSinceStart = daysBetween(from: start, to: referenceDay, calendar: calendar)
        return daysSinceStart <= RecoveryDisruptorHeuristics.activeEpisodeMaxAgeDays
    }

    private static func daysBetween(from: Date, to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private static func percentile(_ sorted: [Double], p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        guard sorted.count > 1 else { return sorted[0] }
        let position = p * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func percentileRank(value: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 50 }
        let below = sorted.filter { $0 < value }.count
        let equal = sorted.filter { $0 == value }.count
        let rank = Double(below) + Double(equal) * 0.5
        return (rank / Double(sorted.count)) * 100
    }
}
