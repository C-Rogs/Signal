import Accelerate
import Foundation
import NaturalLanguage
import os

private actor NLEmbeddingGlobalGate {
    static let shared = NLEmbeddingGlobalGate()

    func run<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await operation()
    }
}

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

    nonisolated func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        try await NLEmbeddingGlobalGate.shared.run {
            try await NLEmbeddingService.shared.embedOnActor(text, kind: kind)
        }
    }

    private func embedOnActor(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        _ = kind
        if !loggedPrefixSkip {
            loggedPrefixSkip = true
            Log.embedding.debug("NL fallback ignores EmbeddingGemma task prefixes")
        }
        return try await embedRaw(text)
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            results.append(try await embed(text, kind: kind))
        }
        return results
    }

    private func embedRaw(_ text: String) async throws -> [Float] {
        guard let embedding else {
            throw EmbeddingServiceError.contextualEmbeddingUnavailable
        }
        try await ensureAssets(for: embedding)

        let result = try await Self.withModelCompilationRetry {
            try embedding.embeddingResult(for: text, language: .english)
        }
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

        let result = try await Self.withModelCompilationRetry {
            try await embedding.requestAssets()
        }
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

    private static func withModelCompilationRetry<T>(
        maxAttempts: Int = 6,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard isTransientModelCompilationError(error), attempt < maxAttempts else {
                    throw error
                }
                let delayNanoseconds = UInt64(attempt) * 500_000_000
                Log.embedding.warning(
                    "NL embed retry attempt=\(attempt, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        throw lastError ?? EmbeddingServiceError.contextualEmbeddingUnavailable
    }

    private static func isTransientModelCompilationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "NLNaturalLanguageErrorDomain" else { return false }
        return nsError.code == 7
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
