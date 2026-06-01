import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct EmbeddingRetrievalTests {
    @Test func embeddingKindPrefixesDiffer() {
        let text = "HRV 42 ms, sleep 7.2 h"
        let document = EmbeddingKind.document.prompted(text)
        let query = EmbeddingKind.query.prompted(text)
        #expect(document != query)
        #expect(document.hasPrefix("title: none | text:"))
        #expect(query.hasPrefix("task: search result | query:"))
    }

    @Test func vectorStoreRetrievalSanityWithSyntheticVectors() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)

        let related = Self.unitVector(dimensions: HealthVectorDimension.embeddingGemma, axis: 0)
        let unrelated = Self.unitVector(dimensions: HealthVectorDimension.embeddingGemma, axis: 1)

        try store.insert(
            dayKey: "mars",
            metricKind: "daily_summary",
            summaryText: "mars-doc",
            vector: related
        )
        try store.insert(
            dayKey: "noise",
            metricKind: "daily_summary",
            summaryText: "noise-doc",
            vector: unrelated
        )

        let neighbors = try store.nearestNeighbors(query: related, k: 2)
        #expect(neighbors.first?.summaryText == "mars-doc")
        let margin = (neighbors.first?.similarity ?? 0) - (neighbors.last?.similarity ?? 0)
        #expect(margin > 0.5)
    }

    #if !targetEnvironment(simulator)
    @Test(.timeLimit(.minutes(10)))
    func gemmaEmbeddingDimensionIs768() async throws {
        let service = GemmaEmbeddingService.shared
        #expect(service.outputDimension == HealthVectorDimension.embeddingGemma)
        let vector = try await service.embed("probe", kind: .document)
        #expect(vector.count == HealthVectorDimension.embeddingGemma)
    }

    @Test(.timeLimit(.minutes(10)))
    func gemmaDocumentAndQueryPrefixesProduceDifferentVectors() async throws {
        let service = GemmaEmbeddingService.shared
        let text = "Resting heart rate 52 bpm after easy run"
        let document = try await service.embed(text, kind: .document)
        let query = try await service.embed(text, kind: .query)
        let similarity = CosineSimilarity.score(query: document, candidate: query)
        #expect(similarity != nil)
        #expect((similarity ?? 1) < 0.99)
    }

    @Test(.timeLimit(.minutes(10)))
    func gemmaRetrievalRoundTripRanksMatchingDocument() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        let service = GemmaEmbeddingService.shared

        try store.deleteAll()

        let marsDoc =
            "Mars, known for its reddish appearance, is often referred to as the Red Planet."
        let noiseDoc =
            "Overnight HRV 88 ms, resting HR 48 bpm, sleep 8.1 hours, active energy 420 kcal."

        try await EmbeddingVectorStoreBridge.indexDocument(
            summaryText: marsDoc,
            dayKey: "mars",
            metricKind: "daily_summary",
            store: store,
            service: service
        )
        try await EmbeddingVectorStoreBridge.indexDocument(
            summaryText: noiseDoc,
            dayKey: "noise",
            metricKind: "daily_summary",
            store: store,
            service: service
        )

        let neighbors = try await EmbeddingVectorStoreBridge.search(
            query: "Which planet is the Red Planet?",
            store: store,
            service: service,
            k: 2
        )

        #expect(neighbors.count == 2)
        #expect(neighbors.first?.summaryText == marsDoc)

        let top = neighbors.first?.similarity ?? 0
        let second = neighbors.last?.similarity ?? 0
        #expect(top - second > 0.15)
    }
    #endif

    private static func unitVector(dimensions: Int, axis: Int) -> [Float] {
        var values = [Float](repeating: 0, count: dimensions)
        guard dimensions > 0, axis >= 0, axis < dimensions else { return values }
        values[axis] = 1
        return values
    }
}
