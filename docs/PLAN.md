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
