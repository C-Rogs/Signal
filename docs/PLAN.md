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

## V1 M6 Hevy CSV importer

- `HevyCSVImporter.swift` + `HevyCSVParser.swift` + `RFC4180CSVParser.swift`
- Per-set rows grouped into sessions (title + start_time), mapped to local calendar days
- `DailyImportEmbeddingPipeline` shared with M5 for persist + embed/upsert
- `Summarizer` workout strings folded into `DailySummary` before `.document` embed
- Tests: `HevyCSVImporterTests`

## V1 M7 HealthKit live pipeline (foreground only)

- `Data/HealthKit/`: `HealthKitManager`, `HealthKitSyncEngine`, `HealthKitSampleIngestor`, `HealthKitDayAggregator`, `HealthKitLookbackDayIndex`, `HealthKitTier1Types`
- Tier 1 read: HRV SDNN, resting HR, active energy, sleep analysis
- `HKAnchoredObjectQuery` per type; anchors in `SyncAnchorStore`
- Affected days fully re-aggregated via shared `DailyMetricAggregationState` (same rules as M5 XML)
- `DailyImportEmbeddingPipeline` persist + embed (Hevy workout text preserved)
- UI: Import tab live sync section; `Sync now`; foreground sync on app active
- Tests: `HealthKitAggregationTests` (aggregator parity with M5)
## V1 M8 background delivery

- `HealthKitBackground.swift`: `HKObserverQuery` + `enableBackgroundDelivery` (hourly) for all Tier 1 types
- Observer sets `HealthKitDirtyFlagStore` only; always calls `completionHandler`
- Deferred `processDelta()` on `protectedDataDidBecomeAvailable` and foreground when dirty and unlocked
- Expanded Tier 1 metrics + `AppleWorkout` model (see metric expansion in repo)

## V1 metric expansion (pre-M8)

- `DailyMetric` expanded scalars (body comp, cardio, activity/load, sleep recovery, BP)
- `DailyNutrition` model (daily macro sums, ~Cronometer/MyFitnessPal days)
- `AppleWorkout` with `activityType`, run mechanics, XML + live HK ingest (separate from Hevy)
- Shared `DailyMetricAggregationState` + `DailyNutritionAggregationState` in XML and `HealthKitSampleIngestor`
- `Summarizer` / `DailySummary`: nutrition, load, recovery, Apple workouts; embed union of metric/nutrition/workout days
- Re-import: delete app, reinstall, re-grant HealthKit, import `export.xml` (no SwiftData migration for schema changes)
