import Accelerate
import Foundation
import NaturalLanguage
import os

actor NLEmbeddingService: EmbeddingService {
    static let shared = NLEmbeddingService()

    private let embedding: NLContextualEmbedding?
    private var assetsReady = false
    private var loggedPrefixSkip = false

    nonisolated let outputDimension: Int

    private init() {
        let model = NLContextualEmbedding(language: .english)
        embedding = model
        outputDimension = model?.dimension ?? 0
    }

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        _ = kind
        if !loggedPrefixSkip {
            loggedPrefixSkip = true
            Log.embedding.debug("NL fallback ignores EmbeddingGemma task prefixes")
        }
        return try await embedRaw(text)
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let vector = try await self.embed(text, kind: kind)
                    return (index, vector)
                }
            }
            var results = Array(repeating: [Float](), count: texts.count)
            for try await (index, vector) in group {
                results[index] = vector
            }
            return results
        }
    }

    private func embedRaw(_ text: String) async throws -> [Float] {
        guard let embedding else {
            throw EmbeddingServiceError.contextualEmbeddingUnavailable
        }
        try await ensureAssets(for: embedding)

        let result = try embedding.embeddingResult(for: text, language: .english)
        var sum = [Double](repeating: 0, count: outputDimension)
        var tokenCount = 0

        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
            guard vector.count == sum.count else { return true }
            for index in sum.indices {
                sum[index] += vector[index]
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0 else {
            throw EmbeddingServiceError.contextualEmbeddingUnavailable
        }

        var pooled = sum.map { Float($0 / Double(tokenCount)) }
        normalizeInPlace(&pooled)
        return pooled
    }

    private func ensureAssets(for embedding: NLContextualEmbedding) async throws {
        guard !assetsReady else { return }
        if embedding.hasAvailableAssets {
            assetsReady = true
            return
        }

        let result = try await embedding.requestAssets()
        switch result {
        case .available:
            break
        case .notAvailable, .error:
            throw EmbeddingServiceError.assetsUnavailable
        @unknown default:
            throw EmbeddingServiceError.assetsUnavailable
        }
        assetsReady = true
        Log.embedding.info("NL contextual embedding assets ready")
    }

    private func normalizeInPlace(_ values: inout [Float]) {
        var normSquared: Float = 0
        values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_svesq(base, 1, &normSquared, vDSP_Length(values.count))
        }
        let norm = sqrtf(normSquared)
        guard norm > 0 else { return }
        for index in values.indices {
            values[index] /= norm
        }
    }
}
