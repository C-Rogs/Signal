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
    private static let embedBatchSize = 24
    private static let metricBatchSize = 64

    static func run(
        fileURL: URL,
        modelContainer: ModelContainer,
        calendar: Calendar,
        onProgress: @Sendable @escaping (HealthImportProgress) -> Void
    ) async throws -> HealthImportResult {
        let started = Date()
        var progress = HealthImportProgress()
        progress.phase = .parsing
        onProgress(progress)

        let aggregation = DailyMetricAggregationState(calendar: calendar)
        let cancelled = { Task.isCancelled }

        let parseDelegate: AppleHealthXMLParserDelegate
        do {
            parseDelegate = try await Task.detached(priority: .userInitiated) {
                try AppleHealthXMLParser.parse(
                    fileURL: fileURL,
                    aggregation: aggregation,
                    isCancelled: cancelled
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

        let sanity = sanityCheck(aggregation: aggregation)
        if let sanity {
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

        let dayStarts = aggregation.allDayStarts()
        var metricsWritten = 0

        for chunk in dayStarts.chunked(into: metricBatchSize) {
            try Task.checkCancellation()
            let metrics = chunk.compactMap { aggregation.mergedMetric(for: $0) }
            let written = try await MainActor.run {
                let context = ModelContext(modelContainer)
                return try DailyMetricStore.upsertBatch(metrics, in: context)
            }
            metricsWritten += written
            progress.dailyMetricsWritten = metricsWritten
            onProgress(progress)
        }

        progress.phase = .embedding
        onProgress(progress)

        let embeddingService = EmbeddingBackend.makeService()

        var vectorsWritten = 0
        for chunk in dayStarts.chunked(into: embedBatchSize) {
            try Task.checkCancellation()
            let metrics = chunk.compactMap { aggregation.mergedMetric(for: $0) }
            guard !metrics.isEmpty else { continue }

            let texts = metrics.map { metric in
                Summarizer.summarize(metric: metric, calendar: calendar).embeddingText
            }
            let dayKeys = metrics.map { Summarizer.dayKey(for: $0.date, calendar: calendar) }

            let vectors = try await embeddingService.embedBatch(texts, kind: .document)
            guard vectors.count == metrics.count else {
                throw EmbeddingServiceError.dimensionMismatch(
                    expected: metrics.count,
                    actual: vectors.count
                )
            }

            try await MainActor.run {
                let context = ModelContext(modelContainer)
                let store = SwiftDataVectorStore(context: context)
                for index in metrics.indices {
                    try store.upsert(
                        dayKey: dayKeys[index],
                        metricKind: DailyMetricStore.dailyVectorKind,
                        summaryText: texts[index],
                        vector: vectors[index]
                    )
                }
                try context.save()
            }

            vectorsWritten += metrics.count
            progress.vectorsWritten = vectorsWritten
            onProgress(progress)
        }

        progress.phase = .finished
        onProgress(progress)

        return await buildResult(
            modelContainer: modelContainer,
            calendar: calendar,
            parseDelegate: parseDelegate,
            started: started,
            cancelled: false,
            sanityWarning: nil
        )
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
                let (summary, text) = Summarizer.summarize(metric: metric, calendar: calendar)
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index ..< end]))
            index = end
        }
        return result
    }
}
