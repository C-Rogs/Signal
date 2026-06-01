import Foundation
import SwiftData
import os

enum DailyMetricStore {
    static let dailyVectorKind = "daily"

    @MainActor
    static func upsert(_ metric: DailyMetric, in context: ModelContext) throws {
        let day = metric.date
        var descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.hrvSDNN_ms = metric.hrvSDNN_ms
            existing.restingHR = metric.restingHR
            existing.activeEnergy_kcal = metric.activeEnergy_kcal
            existing.sleepHours = metric.sleepHours
            existing.source = metric.source
        } else {
            context.insert(metric)
        }
    }

    @MainActor
    static func upsertBatch(_ metrics: [DailyMetric], in context: ModelContext) throws -> Int {
        guard !metrics.isEmpty else { return 0 }
        for metric in metrics {
            try upsert(metric, in: context)
        }
        try context.save()
        return metrics.count
    }

    @MainActor
    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<DailyMetric>())
    }

    @MainActor
    static func fetchSpotCheckDays(
        in context: ModelContext,
        calendar: Calendar,
        limit: Int = 3
    ) throws -> [DailyMetric] {
        let descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        let filtered = all.filter {
            ($0.sleepHours ?? 0) > 0 && ($0.activeEnergy_kcal ?? 0) > 0
        }
        return Array(filtered.prefix(limit))
    }
}
