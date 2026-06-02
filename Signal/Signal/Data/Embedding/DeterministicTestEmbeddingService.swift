import Foundation

/// Stable unit vectors for simulator integration tests (avoids NL E5 compile flakiness).
struct DeterministicTestEmbeddingService: EmbeddingService, Sendable {
    static let shared = DeterministicTestEmbeddingService()

    let outputDimension = HealthVectorDimension.embeddingGemma

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        _ = kind
        var vector = [Float](repeating: 0, count: outputDimension)
        let hash = abs(text.hashValue)
        vector[hash % outputDimension] = 1
        return vector
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for text in texts {
            vectors.append(try await embed(text, kind: kind))
        }
        return vectors
    }
}
