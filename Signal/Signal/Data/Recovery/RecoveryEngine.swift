import Foundation
import os
import SwiftData

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

actor RecoveryEngine {
    static let shared = RecoveryEngine()

    func computeScore(in context: ModelContext) async -> RecoveryScore {
        await MainActor.run {
            let metrics = Self.fetchMetricSnapshots(in: context)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let referenceDay = calendar.startOfDay(for: Date())
            let score = RecoveryScoreCalculator.compute(
                metrics: metrics,
                referenceDay: referenceDay,
                calendar: calendar
            )
            Log.recovery.info(
                "recovery score=\(score.value, format: .fixed(precision: 0), privacy: .public) classification=\(score.hrvClassification.rawValue, privacy: .public) confidence=\(score.confidence.rawValue, privacy: .public)"
            )
            return score
        }
    }

    nonisolated static func rollingMeans(
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

    private nonisolated static func windowMean(
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

    private nonisolated static func metricsInWindow(
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

    private nonisolated static func arithmeticMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    @MainActor
    private static func fetchMetricSnapshots(in context: ModelContext) -> [DailyMetricSnapshot] {
        let descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { DailyMetricSnapshot(metric: $0) }
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
