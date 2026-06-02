import Foundation
import os
import SwiftData

struct DiagnosticsRetrievalRun: Sendable, Equatable {
    let query: String
    let mode: QueryRetrievalMode
    let hits: [RAGSearchHit]
    let temporalWindow: TemporalQueryWindow?
    let usedTemporalFilter: Bool
    let usedRecencyRanking: Bool
    let fallbackToGlobal: Bool
    let footnote: String?
    let errorMessage: String?

    var succeeded: Bool { errorMessage == nil }
}

enum DiagnosticsRetrievalRunner {
    static let displayTopK = 3
    private static let retrievalTopK = DiagnosticsRetrieval.defaultTopK

    static func run(
        query: String,
        modelContainer: ModelContainer,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        displayHitCount: Int = 3
    ) async -> DiagnosticsRetrievalRun {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = QueryRetrievalMode.resolve(in: trimmed, referenceDate: referenceDate, calendar: calendar)

        let context = ModelContext(modelContainer)
        let store = SwiftDataVectorStore(context: context)
        let service = EmbeddingBackend.makeService()

        do {
            let vectorCount = try store.count()
            guard vectorCount > 0 else {
                return DiagnosticsRetrievalRun(
                    query: trimmed,
                    mode: mode,
                    hits: [],
                    temporalWindow: nil,
                    usedTemporalFilter: false,
                    usedRecencyRanking: false,
                    fallbackToGlobal: false,
                    footnote: nil,
                    errorMessage: "No HealthVector rows yet. Import Health or Hevy data first."
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
                searchPoolK = retrievalTopK
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
                searchPoolK = retrievalTopK
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
                topK: retrievalTopK
            )

            let hits = outcome.neighbors.prefix(displayHitCount).map {
                RAGSearchHit(dayKey: $0.dayKey, summaryText: $0.summaryText, score: $0.similarity)
            }

            Log.embedding.info(
                "diagnostics retrieval run queryChars=\(trimmed.count, privacy: .public) hits=\(hits.count, privacy: .public) temporal=\(outcome.usedTemporalFilter, privacy: .public) recency=\(outcome.usedRecencyRanking, privacy: .public)"
            )

            return DiagnosticsRetrievalRun(
                query: trimmed,
                mode: mode,
                hits: Array(hits),
                temporalWindow: temporalWindow,
                usedTemporalFilter: outcome.usedTemporalFilter,
                usedRecencyRanking: outcome.usedRecencyRanking,
                fallbackToGlobal: outcome.fallbackToGlobal,
                footnote: outcome.footnote,
                errorMessage: nil
            )
        } catch {
            Log.embedding.error(
                "diagnostics retrieval run failed: \(String(describing: error), privacy: .public)"
            )
            return DiagnosticsRetrievalRun(
                query: trimmed,
                mode: mode,
                hits: [],
                temporalWindow: nil,
                usedTemporalFilter: false,
                usedRecencyRanking: false,
                fallbackToGlobal: false,
                footnote: nil,
                errorMessage: describeFailure(error)
            )
        }
    }

    private static func describeFailure(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

extension QueryRetrievalMode {
    var uatModeLabel: String {
        switch self {
        case .fixedWindow(let window):
            return "window(\(window.label))"
        case .recencyRanking:
            return "recency"
        case .pureCosine:
            return "cosine"
        }
    }
}
