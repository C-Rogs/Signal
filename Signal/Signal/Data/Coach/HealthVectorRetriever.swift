import Foundation
import SwiftData
import os

struct HealthVectorRetrievalOutcome: Sendable {
    let summaries: [String]
    let neighbors: [VectorNeighbor]
    let mode: QueryRetrievalMode
    let temporalWindow: TemporalQueryWindow?
    let usedTemporalFilter: Bool
    let usedRecencyRanking: Bool
    let fallbackToGlobal: Bool
    let footnote: String?
}

enum HealthVectorRetriever {
    static func retrieve(
        query: String,
        k: Int,
        modelContainer: ModelContainer,
        referenceDate: Date,
        calendar: Calendar = SchedulingCalendar.make()
    ) async throws -> [String] {
        try await retrieveDetailed(
            query: query,
            k: k,
            modelContainer: modelContainer,
            referenceDate: referenceDate,
            calendar: calendar
        ).summaries
    }

    static func retrieveDetailed(
        query: String,
        k: Int,
        modelContainer: ModelContainer,
        referenceDate: Date,
        calendar: Calendar = SchedulingCalendar.make()
    ) async throws -> HealthVectorRetrievalOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = QueryRetrievalMode.resolve(in: trimmed, referenceDate: referenceDate, calendar: calendar)
        guard !trimmed.isEmpty, k > 0 else {
            return HealthVectorRetrievalOutcome(
                summaries: [],
                neighbors: [],
                mode: mode,
                temporalWindow: nil,
                usedTemporalFilter: false,
                usedRecencyRanking: false,
                fallbackToGlobal: false,
                footnote: nil
            )
        }

        let service = EmbeddingBackend.makeService()
        let context = ModelContext(modelContainer)
        let store = SwiftDataVectorStore(context: context)
        let vectorCount = try store.count()
        guard vectorCount > 0 else {
            return HealthVectorRetrievalOutcome(
                summaries: [],
                neighbors: [],
                mode: mode,
                temporalWindow: nil,
                usedTemporalFilter: false,
                usedRecencyRanking: false,
                fallbackToGlobal: false,
                footnote: nil
            )
        }

        let temporalWindow: TemporalQueryWindow?
        let recencyIntent: Bool
        let searchPoolK: Int
        let fromDayKey: String?
        let toDayKey: String?

        switch mode {
        case .fixedWindow(let window):
            temporalWindow = window
            recencyIntent = false
            searchPoolK = max(k, DiagnosticsRetrieval.defaultTopK)
            fromDayKey = window.fromDayKey
            toDayKey = window.toDayKey
        case .recencyRanking:
            temporalWindow = nil
            recencyIntent = true
            searchPoolK = vectorCount
            fromDayKey = nil
            toDayKey = nil
        case .pureCosine:
            temporalWindow = nil
            recencyIntent = false
            searchPoolK = max(k, DiagnosticsRetrieval.defaultTopK)
            fromDayKey = nil
            toDayKey = nil
        }

        let rawNeighbors = try await EmbeddingVectorStoreBridge.search(
            query: trimmed,
            store: store,
            service: service,
            k: searchPoolK,
            fromDayKey: fromDayKey,
            toDayKey: toDayKey
        )

        let outcome = DiagnosticsRetrieval.rankedNeighbors(
            rawNeighbors,
            temporalWindow: temporalWindow,
            recencyIntent: recencyIntent,
            topK: k
        )

        let summaries = outcome.neighbors.map(\.summaryText)
        Log.coach.info(
            "health vector retrieve hits=\(summaries.count, privacy: .public) temporal=\(outcome.usedTemporalFilter, privacy: .public) recency=\(outcome.usedRecencyRanking, privacy: .public)"
        )

        return HealthVectorRetrievalOutcome(
            summaries: summaries,
            neighbors: outcome.neighbors,
            mode: mode,
            temporalWindow: temporalWindow,
            usedTemporalFilter: outcome.usedTemporalFilter,
            usedRecencyRanking: outcome.usedRecencyRanking,
            fallbackToGlobal: outcome.fallbackToGlobal,
            footnote: outcome.footnote
        )
    }
}
