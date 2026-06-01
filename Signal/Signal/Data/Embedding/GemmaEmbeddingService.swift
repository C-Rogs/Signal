import Foundation
import MLX
import MLXEmbedders
import MLXEmbeddersHFAPI
import MLXEmbeddersTokenizers
import MLXLMCommon
import os

actor GemmaEmbeddingService: EmbeddingService {
    static let shared = GemmaEmbeddingService()

    static let modelID = "mlx-community/embeddinggemma-300m-4bit"

    nonisolated let outputDimension = HealthVectorDimension.embeddingGemma

    private var container: EmbedderModelContainer?
    private var loadTask: Task<EmbedderModelContainer, Error>?

    private init() {}

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        let vectors = try await embedBatch([text], kind: kind)
        guard let first = vectors.first else {
            throw EmbeddingServiceError.modelNotLoaded
        }
        return first
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        let modelContainer = try await ensureLoaded()
        let prompted = texts.map { kind.prompted($0) }

        return try await modelContainer.perform { context in
            let tokenizer = context.tokenizer
            let encoded = prompted.map {
                tokenizer.encode(text: $0, addSpecialTokens: true)
            }
            let maxLength = encoded.reduce(into: 1) { acc, elem in
                acc = max(acc, elem.count)
            }
            let eosToken = tokenizer.eosTokenId ?? 0

            let padded = stacked(
                encoded.map { tokens in
                    MLXArray(
                        tokens + Array(repeating: eosToken, count: maxLength - tokens.count)
                    )
                }
            )

            let mask = padded .!= eosToken
            let tokenTypes = MLXArray.zeros(like: padded)

            let modelOutput = context.model(
                padded,
                positionIds: nil,
                tokenTypeIds: tokenTypes,
                attentionMask: mask
            )

            let pooled = context.pooling(
                modelOutput,
                mask: mask,
                normalize: true,
                applyLayerNorm: true
            )
            pooled.eval()

            let rows = pooled.shape[0]
            var results = [[Float]]()
            results.reserveCapacity(rows)
            for index in 0 ..< rows {
                let row = pooled[index]
                let values = row.asArray(Float.self)
                guard values.count == HealthVectorDimension.embeddingGemma else {
                    throw EmbeddingServiceError.dimensionMismatch(
                        expected: HealthVectorDimension.embeddingGemma,
                        actual: values.count
                    )
                }
                results.append(values)
            }
            return results
        }
    }

    func ensureLoaded() async throws -> EmbedderModelContainer {
        if let container {
            return container
        }
        if let loadTask {
            let loaded = try await loadTask.value
            container = loaded
            return loaded
        }

        let task = Task<EmbedderModelContainer, Error> {
            try await Self.loadContainer()
        }
        loadTask = task
        defer { loadTask = nil }

        do {
            let loaded = try await task.value
            container = loaded
            Log.embedding.info("embedding model ready id=\(Self.modelID, privacy: .public)")
            return loaded
        } catch {
            Log.embedding.error("embedding model load failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func loadContainer() async throws -> EmbedderModelContainer {
        let showsDownloadUI = !isModelLikelyCached()
        if showsDownloadUI {
            await EmbeddingDownloadState.shared.begin(message: "Preparing embedding model")
        }

        do {
            let cacheURL = try hubCacheDirectory()
            let hub = HubClient(cache: HubCache(location: .fixed(directory: cacheURL)))
            let configuration = ModelConfiguration(id: modelID)

            let container = try await EmbedderModelFactory.shared.loadContainer(
                from: hub,
                configuration: configuration,
                progressHandler: { progress in
                    Task { @MainActor in
                        if showsDownloadUI, EmbeddingDownloadState.shared.phase != .downloading {
                            EmbeddingDownloadState.shared.begin(message: "Downloading embedding model")
                        }
                        EmbeddingDownloadState.shared.update(progress: progress)
                    }
                }
            )

            await EmbeddingDownloadState.shared.markReady()
            return container
        } catch {
            await EmbeddingDownloadState.shared.fail(Self.userFacingLoadError(error))
            throw error
        }
    }

    private static func isModelLikelyCached() -> Bool {
        guard let hub = try? hubCacheDirectory() else { return false }
        let sanitized = modelID.replacingOccurrences(of: "/", with: "--")
        let modelDir = hub.appending(path: "models--\(sanitized)", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    private static func userFacingLoadError(_ error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("401")
            || description.contains("403")
            || description.contains("gated")
            || description.contains("authorized")
            || description.contains("access")
        {
            return """
            Accept the Gemma license on Hugging Face for mlx-community/embeddinggemma-300m-4bit, \
            then tap Retry. First download needs network; later launches use the on-device cache.
            """
        }
        return "Embedding model could not load. Check network, then tap Retry."
    }

    private static func hubCacheDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let hub = support.appending(path: "HuggingFace/hub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        Log.embedding.info("hub cache path=\(hub.path, privacy: .public)")
        return hub
    }
}
