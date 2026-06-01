# Signal build plan (repo copy)

Canonical detail lives in `build-a-very-detailed-foamy-pixel.md`. This file tracks agent-executable deltas.

## V1 M2 storage layer

### Part A (SwiftData metrics)
- `DailyMetric`, `RecoverySnapshot`, `SyncAnchor` models
- `SignalModelContainer` wired in `SignalApp`
- Unit test: insert/fetch `DailyMetric`

### Part B (vector store, pure Swift)
ObjectBox was dropped (corpus is ~3–4k vectors; brute-force cosine is enough).

- `HealthVector` SwiftData `@Model`: `dayKey`, `metricKind`, `summaryText`, `vector: [Float]` (768 dims)
- `VectorStore` protocol + `SwiftDataVectorStore`
- `nearestNeighbors`: fetch all rows, cosine via Accelerate `vDSP_dotpr` / `vDSP_svesq`, sort desc, top-k
- Logged `do/catch` with `Log.vectorstore`
- Unit test: ~50 random vectors + one target; query ranks target first; `count` / `deleteAll`

### SPM
- **MLX Swift** only (M3 embeddings). No ObjectBox.

## V1 M3 embedding service

- `Data/Embedding/`: `EmbeddingService`, `GemmaEmbeddingService`, `NLEmbeddingService`, `EmbeddingVectorStoreBridge`, `EmbeddingDownloadState`
- Model: `mlx-community/embeddinggemma-300m-4bit`, Hub cache under Application Support
- Prefixes: `.document` / `.query` per EmbeddingGemma model card
- Tests: `EmbeddingRetrievalTests` (MLX tests device-only)
- **SPM (human):** see [M3_SPM_SETUP.md](M3_SPM_SETUP.md)

## V1 M4 normalization layer

- `Data/Normalization/DailySummary.swift`: Codable uniform schema (`date`, `hrvSDNN`, `restingHR`, `activeEnergy`, `sleepHours`, `workoutsSummary`, `recoveryScore` nil until M9)
- `Data/Normalization/Summarizer.swift`: `DailyMetric` + optional workout strings → `DailySummary` JSON + template-stable embedding text; missing metrics omitted
- Tests: `SummarizerTests` (JSON round-trip, text snapshot, sparse day)
