import Foundation
import SwiftData
import UIKit

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
                    let metric = try DailyMetricStore.fetchMetric(for: dayStart, in: context)
                    let nutrition = try DailyNutritionStore.fetch(for: dayStart, in: context)
                    let sessions = try WorkoutStore.fetchSessions(
                        for: dayStart,
                        source: workoutSource,
                        in: context
                    )
                    let appleWorkouts = try AppleWorkoutStore.fetchWorkouts(
                        for: dayStart,
                        calendar: calendar,
                        in: context
                    )
                    let hevySummaries = sessions.map { Summarizer.renderSessionSummary($0) }

                    guard metric != nil || nutrition != nil || !sessions.isEmpty || !appleWorkouts.isEmpty else {
                        continue
                    }

                    let (_, text) = Summarizer.summarize(
                        day: dayStart,
                        metric: metric,
                        nutrition: nutrition,
                        workoutSummaries: hevySummaries,
                        appleWorkouts: appleWorkouts,
                        calendar: calendar
                    )
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }
                    let dayKey = Summarizer.dayKey(for: dayStart, calendar: calendar)
                    items.append((dayKey, text))
                }
                return items
            }
            guard !batch.isEmpty else { continue }

            var embeddedItems: [(dayKey: String, embeddingText: String, vector: [Float])] = []
            embeddedItems.reserveCapacity(batch.count)
            for item in batch {
                try Task.checkCancellation()
                try await assertEmbeddingPermitted()
                let vector = try await embeddingService.embed(item.embeddingText, kind: .document)
                embeddedItems.append((item.dayKey, item.embeddingText, vector))
            }

            guard !embeddedItems.isEmpty else { continue }
            try await MainActor.run {
                let context = ModelContext(modelContainer)
                let store = SwiftDataVectorStore(context: context)
                for item in embeddedItems {
                    try store.upsert(
                        dayKey: item.dayKey,
                        metricKind: DailyMetricStore.dailyVectorKind,
                        summaryText: item.embeddingText,
                        vector: item.vector,
                        saveImmediately: false
                    )
                }
                try context.save()
            }
            vectorsWritten += embeddedItems.count
            onVectorsWritten(vectorsWritten)
        }
        return vectorsWritten
    }

    private static func assertEmbeddingPermitted() async throws {
        try Task.checkCancellation()
        let permitted = await MainActor.run { EmbeddingRunPolicy.mayUseMetal }
        guard permitted else {
            throw CancellationError()
        }
    }
}

extension Array {
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
