import Foundation
import os

enum RecoveryWindow: Int, CaseIterable, Sendable, Identifiable {
    case seven = 7
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var label: String {
        "\(rawValue)d"
    }
}

struct DailyMetricSnapshot: Sendable, Equatable {
    let date: Date
    let hrvSDNN: Double?
    let restingHR: Double?
    let activeEnergy: Double?
    let sleepHours: Double?
    let bodyMassKg: Double?
    let stepCount: Double?
    let appleExerciseMinutes: Double?
}

struct WindowMean: Sendable, Equatable {
    let hrvSDNN: Double?
    let restingHR: Double?
    let sampleDays: Int
}

struct MetricRollingMeans: Sendable, Equatable {
    let sevenDay: WindowMean
    let thirtyDay: WindowMean
    let sixtyDay: WindowMean

    func mean(for window: RecoveryWindow) -> WindowMean {
        switch window {
        case .seven: sevenDay
        case .thirty: thirtyDay
        case .sixty: sixtyDay
        }
    }
}

enum RecoveryStatus: String, Sendable {
    case recovered
    case steady
    case fatigued
    case unknown
}

struct RecoveryIndicator: Sendable, Equatable {
    let score: Double?
    let status: RecoveryStatus
    let todayHRV: Double?
    let todayRestingHR: Double?
    let baselineHRV: Double?
    let baselineRestingHR: Double?
}

enum RecoveryEngine {
    private static let baselineWindowDays = 30

    static func rollingMeans(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> MetricRollingMeans {
        let end = calendar.startOfDay(for: referenceDay)
        return MetricRollingMeans(
            sevenDay: windowMean(metrics: metrics, end: end, days: 7, calendar: calendar),
            thirtyDay: windowMean(metrics: metrics, end: end, days: 30, calendar: calendar),
            sixtyDay: windowMean(metrics: metrics, end: end, days: 60, calendar: calendar)
        )
    }

    static func recoveryIndicator(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> RecoveryIndicator {
        let end = calendar.startOfDay(for: referenceDay)
        let today = metrics.first { calendar.isDate($0.date, inSameDayAs: end) }
        let baselineMetrics = metricsInWindow(
            metrics: metrics,
            end: end,
            days: baselineWindowDays,
            calendar: calendar,
            excludingReferenceDay: true
        )

        let baselineHRV = arithmeticMean(baselineMetrics.compactMap(\.hrvSDNN))
        let baselineRHR = arithmeticMean(baselineMetrics.compactMap(\.restingHR))
        let todayHRV = today?.hrvSDNN
        let todayRHR = today?.restingHR

        var components: [Double] = []
        if let todayHRV, let baselineHRV, baselineHRV > 0 {
            components.append(min(1.15, todayHRV / baselineHRV) / 1.15)
        }
        if let todayRHR, let baselineRHR, todayRHR > 0 {
            components.append(min(1.15, baselineRHR / todayRHR) / 1.15)
        }

        guard !components.isEmpty else {
            Log.recovery.info("recovery indicator unavailable; insufficient HRV or RHR data")
            return RecoveryIndicator(
                score: nil,
                status: .unknown,
                todayHRV: todayHRV,
                todayRestingHR: todayRHR,
                baselineHRV: baselineHRV,
                baselineRestingHR: baselineRHR
            )
        }

        let normalized = components.reduce(0, +) / Double(components.count)
        let score = (normalized * 100).rounded()
        let status = status(forScore: score)

        Log.recovery.info(
            "recovery score=\(score, format: .fixed(precision: 0), privacy: .public) status=\(status.rawValue, privacy: .public)"
        )

        return RecoveryIndicator(
            score: score,
            status: status,
            todayHRV: todayHRV,
            todayRestingHR: todayRHR,
            baselineHRV: baselineHRV,
            baselineRestingHR: baselineRHR
        )
    }

    private static func status(forScore score: Double) -> RecoveryStatus {
        switch score {
        case 70...:
            .recovered
        case 45..<70:
            .steady
        default:
            .fatigued
        }
    }

    private static func windowMean(
        metrics: [DailyMetricSnapshot],
        end: Date,
        days: Int,
        calendar: Calendar
    ) -> WindowMean {
        let slice = metricsInWindow(
            metrics: metrics,
            end: end,
            days: days,
            calendar: calendar,
            excludingReferenceDay: false
        )
        return WindowMean(
            hrvSDNN: arithmeticMean(slice.compactMap(\.hrvSDNN)),
            restingHR: arithmeticMean(slice.compactMap(\.restingHR)),
            sampleDays: slice.count
        )
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

extension DailyMetricSnapshot {
    init(metric: DailyMetric) {
        date = metric.date
        hrvSDNN = metric.hrvSDNN_ms
        restingHR = metric.restingHR
        activeEnergy = metric.activeEnergy_kcal
        sleepHours = metric.sleepHours
        bodyMassKg = metric.bodyMassKg
        stepCount = metric.stepCount
        appleExerciseMinutes = metric.appleExerciseMinutes
    }
}
