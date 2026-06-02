import Foundation
import os

enum EmbeddingVectorStoreBridge {
    static func indexDocument(
        summaryText: String,
        dayKey: String,
        metricKind: String,
        store: any VectorStore,
        service: any EmbeddingService
    ) async throws {
        let vector = try await service.embed(summaryText, kind: .document)
        try validateDimension(vector, service: service)
        try store.insert(
            dayKey: dayKey,
            metricKind: metricKind,
            summaryText: summaryText,
            vector: vector
        )
        Log.embedding.info("indexed document dayKey=\(dayKey, privacy: .public)")
    }

    static func search(
        query: String,
        store: any VectorStore,
        service: any EmbeddingService,
        k: Int,
        fromDayKey: String? = nil,
        toDayKey: String? = nil
    ) async throws -> [VectorNeighbor] {
        let vector = try await service.embed(query, kind: .query)
        try validateDimension(vector, service: service)
        let neighbors = try store.nearestNeighbors(
            query: vector,
            k: k,
            fromDayKey: fromDayKey,
            toDayKey: toDayKey
        )
        Log.embedding.info("search queryChars=\(query.count, privacy: .public) hits=\(neighbors.count, privacy: .public)")
        return neighbors
    }

    private static func validateDimension(_ vector: [Float], service: any EmbeddingService) throws {
        let expected = service.outputDimension
        guard expected > 0 else {
            throw EmbeddingServiceError.contextualEmbeddingUnavailable
        }
        guard vector.count == expected else {
            Log.embedding.error(
                "vector dimension \(vector.count, privacy: .public) does not match service \(expected, privacy: .public)"
            )
            throw EmbeddingServiceError.dimensionMismatch(
                expected: expected,
                actual: vector.count
            )
        }
    }
}
