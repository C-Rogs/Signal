import Foundation
import SwiftData
import os

enum DataQualityProcessor {
    @MainActor
    static func apply(to metrics: [DailyMetric], in context: ModelContext) throws {
        guard !metrics.isEmpty else { return }
        let sortedHistory = try fetchSortedMetrics(in: context)
        var flagsInserted = 0
        for metric in metrics {
            flagsInserted += try apply(to: metric, history: sortedHistory, in: context)
        }
        if flagsInserted > 0 {
            try context.save()
            Log.sync.info("data quality flags inserted count=\(flagsInserted, privacy: .public)")
        }
    }

    @MainActor
    static func apply(to metric: DailyMetric, in context: ModelContext) throws {
        let history = try fetchSortedMetrics(in: context)
        let inserted = try apply(to: metric, history: history, in: context)
        if inserted > 0 {
            try context.save()
        }
    }

    @MainActor
    private static func apply(
        to metric: DailyMetric,
        history: [DailyMetric],
        in context: ModelContext
    ) throws -> Int {
        var inserted = 0
        let day = metric.date

        if let spo2 = metric.bloodOxygenPct {
            let validation = DataQualityValidator.validateSpO2(spo2)
            if let corrected = validation.correctedValue {
                try insertFlag(
                    date: day,
                    metricKind: DataQualityValidator.spo2MetricKind,
                    originalValue: spo2,
                    issue: validation.issue?.rawValue ?? DataQualityIssue.corrected.rawValue,
                    wasCorrected: true,
                    in: context
                )
                metric.bloodOxygenPct = corrected
                inserted += 1
            }
        }

        if let restingHR = metric.restingHR {
            let validation = DataQualityValidator.validateRestingHR(restingHR)
            if validation.issue == .suspectOutlier {
                try insertFlag(
                    date: day,
                    metricKind: DataQualityValidator.restingHRMetricKind,
                    originalValue: restingHR,
                    issue: DataQualityIssue.suspectOutlier.rawValue,
                    wasCorrected: false,
                    in: context
                )
                inserted += 1
            }
        }

        if let hrv = metric.hrvSDNN_ms {
            let prior = hrvHistory(before: day, from: history)
            let validation = DataQualityValidator.validateHRV(sdnn: hrv, priorValues: prior)
            if validation.issue == .statisticalOutlier {
                try insertFlag(
                    date: day,
                    metricKind: DataQualityValidator.hrvMetricKind,
                    originalValue: hrv,
                    issue: DataQualityIssue.statisticalOutlier.rawValue,
                    wasCorrected: false,
                    in: context
                )
                inserted += 1
            }
        }

        return inserted
    }

    @MainActor
    private static func insertFlag(
        date: Date,
        metricKind: String,
        originalValue: Double,
        issue: String,
        wasCorrected: Bool,
        in context: ModelContext
    ) throws {
        let flagDate = date
        let flagMetricKind = metricKind
        let flagIssue = issue
        var descriptor = FetchDescriptor<DataQualityFlag>(
            predicate: #Predicate { flag in
                flag.date == flagDate
                    && flag.metricKind == flagMetricKind
                    && flag.issue == flagIssue
            }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(
            DataQualityFlag(
                date: date,
                metricKind: metricKind,
                originalValue: originalValue,
                issue: issue,
                wasCorrected: wasCorrected
            )
        )
    }

    @MainActor
    private static func fetchSortedMetrics(in context: ModelContext) throws -> [DailyMetric] {
        try context.fetch(
            FetchDescriptor<DailyMetric>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )
    }

    private static func hrvHistory(before day: Date, from history: [DailyMetric]) -> [Double] {
        let windowStart = Calendar.current.date(byAdding: .day, value: -30, to: day) ?? day
        return history
            .filter { $0.date < day && $0.date >= windowStart }
            .compactMap(\.hrvSDNN_ms)
    }
}
