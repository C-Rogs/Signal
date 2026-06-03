import Foundation

enum RecoveryConfidence: String, Sendable, Equatable {
    case low
    case medium
    case high
}

struct RecoveryScoreBreakdown: Sendable, Equatable {
    let hrvTerm: Double
    let rhrTerm: Double
    let sleepTerm: Double
    let total: Double
}

struct RecoveryScore: Sendable, Equatable {
    let value: Double
    let hrvClassification: HRVBandClassification
    let hrvAnalysis: HRVAnalysis?
    let rhrDelta: Double?
    let sleepDelta: Double?
    let confidence: RecoveryConfidence
    let breakdown: RecoveryScoreBreakdown
    let todayHRV: Double?
    let todayRestingHR: Double?
}

enum RecoveryScoreCalculator {
    private static let baselineWindowDays = 30

    static func compute(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> RecoveryScore {
        let end = calendar.startOfDay(for: referenceDay)
        let today = metrics.first { calendar.isDate($0.date, inSameDayAs: end) }

        let hrvSeries = metrics
            .filter { $0.hrvSDNN != nil }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, sdnn: $0.hrvSDNN!) }

        let hrvAnalysis: HRVAnalysis? = hrvSeries.isEmpty ? nil : HRVAnalyzer.analyze(hrvSeries)
        let classification = hrvAnalysis?.classification ?? .insufficientData
        let confidence = confidence(forHRVDataPoints: hrvAnalysis?.dataPointsUsed ?? 0)

        let baselineMetrics = metricsInWindow(
            metrics: metrics,
            end: end,
            days: baselineWindowDays,
            calendar: calendar,
            excludingReferenceDay: true
        )
        let baselineRHR = arithmeticMean(baselineMetrics.compactMap(\.restingHR))
        let baselineSleep = arithmeticMean(baselineMetrics.compactMap(\.sleepHours))

        let todayRHR = today?.restingHR
        let todaySleep = today?.sleepHours
        let rhrDelta: Double? = delta(today: todayRHR, baseline: baselineRHR)
        let sleepDelta: Double? = delta(today: todaySleep, baseline: baselineSleep)

        let breakdown = composeBreakdown(
            classification: classification,
            rhrDelta: rhrDelta,
            sleepDelta: sleepDelta
        )

        return RecoveryScore(
            value: breakdown.total,
            hrvClassification: classification,
            hrvAnalysis: hrvAnalysis,
            rhrDelta: rhrDelta,
            sleepDelta: sleepDelta,
            confidence: confidence,
            breakdown: breakdown,
            todayHRV: today?.hrvSDNN,
            todayRestingHR: todayRHR
        )
    }

    static func composeBreakdown(
        classification: HRVBandClassification,
        rhrDelta: Double?,
        sleepDelta: Double?
    ) -> RecoveryScoreBreakdown {
        let hrvTerm = hrvContribution(for: classification)
        let rhrTerm = rhrContribution(for: rhrDelta)
        let sleepTerm = sleepContribution(for: sleepDelta)
        let raw = 50 + hrvTerm + rhrTerm + sleepTerm
        let total = min(100, max(0, raw))
        return RecoveryScoreBreakdown(
            hrvTerm: hrvTerm,
            rhrTerm: rhrTerm,
            sleepTerm: sleepTerm,
            total: total
        )
    }

    static func confidence(forHRVDataPoints count: Int) -> RecoveryConfidence {
        switch count {
        case 30...:
            .high
        case 14..<30:
            .medium
        default:
            .low
        }
    }

    private static func hrvContribution(for classification: HRVBandClassification) -> Double {
        switch classification {
        case .aboveUpperBand: 20
        case .withinBand: 0
        case .belowLowerBand: -20
        case .insufficientData: 0
        }
    }

    private static func rhrContribution(for delta: Double?) -> Double {
        guard let delta else { return 0 }
        if delta <= -3 { return 10 }
        if delta <= 3 { return 0 }
        if delta < 7 { return -10 }
        return -20
    }

    private static func sleepContribution(for delta: Double?) -> Double {
        guard let delta else { return 0 }
        if delta >= 1 { return 10 }
        if delta >= -1 { return 0 }
        return -10
    }

    private static func delta(today: Double?, baseline: Double?) -> Double? {
        guard let today, let baseline else { return nil }
        return today - baseline
    }

    private static func metricsInWindow(
        metrics: [DailyMetricSnapshot],
        end: Date,
        days: Int,
        calendar: Calendar,
        excludingReferenceDay: Bool
    ) -> [DailyMetricSnapshot] {
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: end)
        else { return [] }

        return metrics.filter { snapshot in
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, day <= end else { return false }
            if excludingReferenceDay, calendar.isDate(day, inSameDayAs: end) {
                return false
            }
            return true
        }
    }

    private static func arithmeticMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
