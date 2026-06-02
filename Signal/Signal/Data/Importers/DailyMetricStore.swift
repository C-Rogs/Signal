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
            existing.bodyMassKg = metric.bodyMassKg
            existing.vo2Max = metric.vo2Max
            existing.respiratoryRate = metric.respiratoryRate
            existing.wristTemperatureDeltaC = metric.wristTemperatureDeltaC
            existing.bloodOxygenPct = metric.bloodOxygenPct
            existing.heartRateMax = metric.heartRateMax
            existing.heartRateAvg = metric.heartRateAvg
            existing.stepCount = metric.stepCount
            existing.basalEnergyKcal = metric.basalEnergyKcal
            existing.bodyFatPercentage = metric.bodyFatPercentage
            existing.leanBodyMassKg = metric.leanBodyMassKg
            existing.walkingHeartRateAvg = metric.walkingHeartRateAvg
            existing.appleExerciseMinutes = metric.appleExerciseMinutes
            existing.appleStandHours = metric.appleStandHours
            existing.physicalEffort = metric.physicalEffort
            existing.timeInDaylightMin = metric.timeInDaylightMin
            existing.sleepingBreathingDisturbances = metric.sleepingBreathingDisturbances
            existing.bloodPressureSystolic = metric.bloodPressureSystolic
            existing.bloodPressureDiastolic = metric.bloodPressureDiastolic
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
    static func fetchMetric(for day: Date, in context: ModelContext) throws -> DailyMetric? {
        var descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    static func fetchMetric(
        for day: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> DailyMetric? {
        try fetchMetric(for: calendar.startOfDay(for: day), in: context)
    }

    @MainActor
    static func ensureDayExists(date: Date, source: String, in context: ModelContext) throws {
        var descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date == date }
        )
        descriptor.fetchLimit = 1
        if try context.fetch(descriptor).first != nil {
            return
        }
        context.insert(DailyMetric(date: date, source: source))
    }

    @MainActor
    static func fetchSpotCheckWorkoutDays(
        in context: ModelContext,
        days: [Date],
        calendar: Calendar,
        limit: Int = 2
    ) throws -> [DailyMetric] {
        guard !days.isEmpty else { return [] }
        let sortedDays = days.sorted(by: >)
        var metrics: [DailyMetric] = []
        metrics.reserveCapacity(min(limit, sortedDays.count))
        for day in sortedDays {
            let dayStart = calendar.startOfDay(for: day)
            if let metric = try fetchMetric(for: dayStart, in: context) {
                metrics.append(metric)
            }
            if metrics.count >= limit {
                break
            }
        }
        return metrics
    }

    @MainActor
    static func fetchDayStarts(
        in context: ModelContext,
        calendar: Calendar,
        withinLastDays days: Int,
        from referenceDate: Date = Date()
    ) throws -> [Date] {
        guard days > 0 else { return [] }
        let end = calendar.startOfDay(for: referenceDate)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else {
            return []
        }
        let descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try context.fetch(descriptor).map(\.date)
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
