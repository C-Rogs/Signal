import Darwin
import Foundation
import SwiftData
import os

struct HealthImportProgress: Sendable {
    var recordsScanned: Int = 0
    var tier1RecordsKept: Int = 0
    var daysAggregated: Int = 0
    var dailyMetricsWritten: Int = 0
    var vectorsWritten: Int = 0
    var phase: Phase = .idle

    enum Phase: String, Sendable {
        case idle
        case parsing
        case persistingMetrics
        case embedding
        case finished
        case failed
        case cancelled
    }
}

struct HealthImportResult: Sendable {
    let recordsScanned: Int
    let tier1RecordsKept: Int
    let dailyMetricCount: Int
    let healthVectorCount: Int
    let elapsedSeconds: TimeInterval
    let peakMemoryBytes: UInt64?
    let spotCheckSummaries: [String]
    let cancelled: Bool
    let sanityWarning: String?
}

enum AppleHealthXMLImporter {
    static func run(
        fileURL: URL,
        modelContainer: ModelContainer,
        calendar: Calendar,
        onParseFinished: (@Sendable () -> Void)? = nil,
        onProgress: @Sendable @escaping (HealthImportProgress) -> Void
    ) async throws -> HealthImportResult {
        let started = Date()
        var progress = HealthImportProgress()
        progress.phase = .parsing
        onProgress(progress)

        let aggregation = DailyMetricAggregationState(calendar: calendar)
        let nutritionAggregation = DailyNutritionAggregationState(calendar: calendar)
        let cancelled = { Task.isCancelled }

        let parseDelegate: AppleHealthXMLParserDelegate
        do {
            parseDelegate = try await Task.detached(priority: .userInitiated) {
                try AppleHealthXMLParser.parse(
                    fileURL: fileURL,
                    aggregation: aggregation,
                    nutritionAggregation: nutritionAggregation,
                    isCancelled: cancelled,
                    onParseProgress: { scanned, tier1 in
                        var snapshot = HealthImportProgress()
                        snapshot.phase = .parsing
                        snapshot.recordsScanned = scanned
                        snapshot.tier1RecordsKept = tier1
                        onProgress(snapshot)
                        if scanned % 50_000 == 0 {
                            Log.import.info(
                                "parse progress scanned=\(scanned, privacy: .public) tier1=\(tier1, privacy: .public)"
                            )
                        }
                    }
                )
            }.value
        } catch AppleHealthXMLParseError.cancelled {
            progress.phase = .cancelled
            onProgress(progress)
            return await buildResult(
                modelContainer: modelContainer,
                calendar: calendar,
                parseDelegate: nil,
                started: started,
                cancelled: true,
                sanityWarning: nil
            )
        }

        progress.recordsScanned = parseDelegate.recordsScanned
        progress.tier1RecordsKept = parseDelegate.tier1RecordsKept
        progress.daysAggregated = aggregation.dayCount
        onProgress(progress)

        onParseFinished?()

        let sanity = sanityCheck(aggregation: aggregation)
        if let sanity {
            aggregation.releaseParsedData()
            progress.phase = .failed
            onProgress(progress)
            Log.import.error("import sanity failed: \(sanity, privacy: .public)")
            return await buildResult(
                modelContainer: modelContainer,
                calendar: calendar,
                parseDelegate: parseDelegate,
                started: started,
                cancelled: false,
                sanityWarning: sanity
            )
        }

        progress.phase = .persistingMetrics
        onProgress(progress)

        let metricDayStarts = aggregation.allDayStarts()
        let nutritionDayStarts = nutritionAggregation.allDayStarts()
        let workoutDayStarts = ImportDayUnion.workoutDayStarts(
            from: parseDelegate.parsedWorkouts,
            calendar: calendar
        )
        let dayStarts = ImportDayUnion.unionDayStarts(
            metricDays: metricDayStarts,
            nutritionDays: nutritionDayStarts,
            workoutDays: workoutDayStarts
        )

        let metricsWritten = try await DailyImportEmbeddingPipeline.persistMetrics(
            dayStarts: metricDayStarts,
            aggregation: aggregation,
            modelContainer: modelContainer
        )

        let nutritionWritten = try await persistNutrition(
            dayStarts: nutritionDayStarts,
            aggregation: nutritionAggregation,
            modelContainer: modelContainer
        )
        Log.import.info("daily nutrition persisted count=\(nutritionWritten, privacy: .public)")

        let workoutsWritten = try await MainActor.run {
            let context = ModelContext(modelContainer)
            return try AppleWorkoutStore.upsertBatch(parseDelegate.parsedWorkouts, in: context)
        }
        Log.import.info("apple workouts persisted count=\(workoutsWritten, privacy: .public)")

        aggregation.releaseParsedData()
        nutritionAggregation.releaseParsedData()

        progress.dailyMetricsWritten = metricsWritten
        onProgress(progress)

        progress.phase = .embedding
        onProgress(progress)

        let embeddingService = EmbeddingBackend.makeService()
        progress.vectorsWritten = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: dayStarts,
            modelContainer: modelContainer,
            calendar: calendar,
            embeddingService: embeddingService,
            workoutSource: HevyCSVImporter.importSource,
            embedBatchSize: DailyImportEmbeddingPipeline.healthEmbedBatchSize
        ) { count in
            progress.vectorsWritten = count
            onProgress(progress)
        }

        progress.phase = .finished
        onProgress(progress)

        NotificationCenter.default.post(name: .healthKitProcessDeltaDidFinish, object: nil)
        await DerivedMetricsService.shared.invalidateCache()

        return await buildResult(
            modelContainer: modelContainer,
            calendar: calendar,
            parseDelegate: parseDelegate,
            started: started,
            cancelled: false,
            sanityWarning: nil
        )
    }

    private static func persistNutrition(
        dayStarts: [Date],
        aggregation: DailyNutritionAggregationState,
        modelContainer: ModelContainer
    ) async throws -> Int {
        var written = 0
        for chunk in dayStarts.chunked(into: DailyImportEmbeddingPipeline.metricBatchSize) {
            try Task.checkCancellation()
            let items = chunk.compactMap { aggregation.mergedNutrition(for: $0) }
            guard !items.isEmpty else { continue }
            let batchWritten = try await MainActor.run {
                let context = ModelContext(modelContainer)
                return try DailyNutritionStore.upsertBatch(items, in: context)
            }
            written += batchWritten
        }
        return written
    }

    private static func sanityCheck(aggregation: DailyMetricAggregationState) -> String? {
        let days = aggregation.allDayStarts()
        guard !days.isEmpty else {
            return "no days aggregated from export"
        }

        var totalSleep: Double = 0
        var totalEnergy: Double = 0
        var daysWithSleep = 0

        for day in days {
            guard let metric = aggregation.mergedMetric(for: day) else { continue }
            if let sleep = metric.sleepHours, sleep > 0 {
                totalSleep += sleep
                daysWithSleep += 1
            }
            if let energy = metric.activeEnergy_kcal {
                totalEnergy += energy
            }
        }

        if daysWithSleep == 0 {
            return "zero days with sleep across entire export"
        }
        if totalEnergy < 1 {
            return "total active energy across export is under 1 kcal"
        }

        let averageSleep = totalSleep / Double(max(daysWithSleep, 1))
        if averageSleep > 24 {
            return "average sleep per wake day exceeds 24 hours (\(averageSleep))"
        }

        return nil
    }

    @MainActor
    private static func buildResult(
        modelContainer: ModelContainer,
        calendar: Calendar,
        parseDelegate: AppleHealthXMLParserDelegate?,
        started: Date,
        cancelled: Bool,
        sanityWarning: String?
    ) async -> HealthImportResult {
        let context = ModelContext(modelContainer)
        let metricCount = (try? DailyMetricStore.count(in: context)) ?? 0
        let vectorCount = (try? SwiftDataVectorStore(context: context).count()) ?? 0

        var spotLines: [String] = []
        if let spotMetrics = try? DailyMetricStore.fetchSpotCheckDays(in: context, calendar: calendar) {
            for metric in spotMetrics {
                let nutrition = try? DailyNutritionStore.fetch(for: metric.date, in: context)
                let appleWorkouts = (try? AppleWorkoutStore.fetchWorkouts(
                    for: metric.date,
                    calendar: calendar,
                    in: context
                )) ?? []
                let (summary, text) = Summarizer.summarize(
                    day: metric.date,
                    metric: metric,
                    nutrition: nutrition,
                    appleWorkouts: appleWorkouts,
                    calendar: calendar
                )
                if let data = try? Summarizer.encodeJSON(summary),
                   let json = String(data: data, encoding: .utf8)
                {
                    Log.import.info("spot-check dayKey=\(summary.date, privacy: .public) json=\(json, privacy: .public)")
                    Log.import.info("spot-check dayKey=\(summary.date, privacy: .public) text=\(text, privacy: .public)")
                    spotLines.append("\(summary.date): \(text)")
                }
            }
        }

        let elapsed = Date().timeIntervalSince(started)
        let peak = MemoryUsage.peakResidentBytes()

        Log.import.info(
            "import complete cancelled=\(cancelled, privacy: .public) scanned=\(parseDelegate?.recordsScanned ?? 0, privacy: .public) tier1=\(parseDelegate?.tier1RecordsKept ?? 0, privacy: .public) metrics=\(metricCount, privacy: .public) vectors=\(vectorCount, privacy: .public) elapsedSec=\(elapsed, format: .fixed(precision: 2), privacy: .public) peakMB=\(Double(peak ?? 0) / 1_048_576, format: .fixed(precision: 1), privacy: .public)"
        )

        return HealthImportResult(
            recordsScanned: parseDelegate?.recordsScanned ?? 0,
            tier1RecordsKept: parseDelegate?.tier1RecordsKept ?? 0,
            dailyMetricCount: metricCount,
            healthVectorCount: vectorCount,
            elapsedSeconds: elapsed,
            peakMemoryBytes: peak,
            spotCheckSummaries: spotLines,
            cancelled: cancelled,
            sanityWarning: sanityWarning
        )
    }
}

enum MemoryUsage {
    static func peakResidentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.resident_size
    }
}
