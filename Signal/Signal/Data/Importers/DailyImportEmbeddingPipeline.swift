import Foundation
import SwiftData

enum DailyImportEmbeddingPipeline {
    static let metricBatchSize = 64
    static let defaultEmbedBatchSize = 8
    static let healthEmbedBatchSize = 2

    static func persistMetrics(
        _ metrics: [DailyMetric],
        modelContainer: ModelContainer
    ) async throws -> Int {
        var metricsWritten = 0
        for chunk in metrics.chunked(into: metricBatchSize) {
            try Task.checkCancellation()
            let written = try await MainActor.run {
                let context = ModelContext(modelContainer)
                return try DailyMetricStore.upsertBatch(chunk, in: context)
            }
            metricsWritten += written
        }
        return metricsWritten
    }

    static func persistMetrics(
        dayStarts: [Date],
        aggregation: DailyMetricAggregationState,
        modelContainer: ModelContainer
    ) async throws -> Int {
        var metricsWritten = 0
        for chunk in dayStarts.chunked(into: metricBatchSize) {
            try Task.checkCancellation()
            let metrics = chunk.compactMap { aggregation.mergedMetric(for: $0) }
            guard !metrics.isEmpty else { continue }
            metricsWritten += try await persistMetrics(metrics, modelContainer: modelContainer)
        }
        return metricsWritten
    }

    static func embedAndUpsert(
        dayStarts: [Date],
        modelContainer: ModelContainer,
        calendar: Calendar,
        embeddingService: any EmbeddingService,
        workoutSource: String = HevyCSVImporter.importSource,
        embedBatchSize: Int = defaultEmbedBatchSize,
        onVectorsWritten: @Sendable (Int) -> Void
    ) async throws -> Int {
        var vectorsWritten = 0
        let batchSize = max(1, embedBatchSize)
        for chunk in dayStarts.chunked(into: batchSize) {
            try Task.checkCancellation()

            let batch: [(dayKey: String, embeddingText: String)] = try await MainActor.run {
                let context = ModelContext(modelContainer)
                var items: [(String, String)] = []
                items.reserveCapacity(chunk.count)
                for day in chunk {
                    let dayStart = calendar.startOfDay(for: day)
                    guard let metric = try DailyMetricStore.fetchMetric(for: dayStart, in: context) else {
                        continue
                    }
                    let sessions = try WorkoutStore.fetchSessions(
                        for: dayStart,
                        source: workoutSource,
                        in: context
                    )
                    let workoutSummaries = sessions.map { Summarizer.renderSessionSummary($0) }
                    let (_, text) = Summarizer.summarize(
                        metric: metric,
                        workoutSummaries: workoutSummaries,
                        calendar: calendar
                    )
                    let dayKey = Summarizer.dayKey(for: metric.date, calendar: calendar)
                    items.append((dayKey, text))
                }
                return items
            }
            guard !batch.isEmpty else { continue }

            for item in batch {
                try Task.checkCancellation()
                let vector = try await embeddingService.embed(item.embeddingText, kind: .document)
                try await MainActor.run {
                    let context = ModelContext(modelContainer)
                    let store = SwiftDataVectorStore(context: context)
                    try store.upsert(
                        dayKey: item.dayKey,
                        metricKind: DailyMetricStore.dailyVectorKind,
                        summaryText: item.embeddingText,
                        vector: vector
                    )
                    try context.save()
                }
                vectorsWritten += 1
                onVectorsWritten(vectorsWritten)
            }
        }
        return vectorsWritten
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
