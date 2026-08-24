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

## V4 M4.5 Coach temporal grounding + FM tool efficiency

Canonical Apple references: TN3193 (4096 token budget), Foundation Models tool calling docs, WWDC25 sessions 248/259/301.

### Problem

Coach infers the wrong calendar day (e.g. May 20 when device clock is June 5) because:

1. No authoritative wall-clock anchor in FM session instructions or tools
2. RAG summaries start with `Health day YYYY-MM-DD.` and the model treats the newest or most relevant line as "today" without comparing dayKeys
3. Metrics section uses the word "today" without tying to wall clock
4. `computeProteinTarget` uses the latest `DailyNutrition` row of any date but labels it "today"

### Semantic rule (important)

**Do not** instruct the model that "Health day lines are past dates."

RAG `Health day` lines are **date-labeled records**: each line describes metrics for that specific calendar day. If the user logged a workout or HealthKit synced today, History will correctly contain `Health day <today's dayKey>.` That line is about today.

The bug is **conflation**, not stale wording:

| Source | Meaning |
|--------|---------|
| Clock anchor (instructions + `getDeviceClock` tool) | Authoritative **current moment** on the device |
| `Health day YYYY-MM-DD` in RAG | Data **for that calendar day** (may equal today, may be older) |
| Metrics "today" labels | Must mean the Clock reference day only |

Instructions must teach the model to **compare** Health day prefixes to the Clock dayKey:

- If `Health day 2026-06-05` and Clock is `2026-06-05`, that RAG line is today's health data.
- If the newest Health day in RAG is `2026-05-20` but Clock is `2026-06-05`, health sync is stale; say so, do not treat May 20 as today.

Optional freshness line in Metrics (when latest `DailyMetric.date` is >1 day before reference day):

`Health sync latest: YYYY-MM-DD.`

### Apple FM architecture (how to implement)

**Instructions** (`LanguageModelSession(instructions:)`): session-wide persona + **runtime Clock anchor** from `Date()` on every coach request. WWDC301 calendar example puts today's date in instructions so the model resolves "tomorrow" and tool date args. Instructions are not truncated when prompt overflows.

**Tools**: model autonomously calls when needed. Max 3 to 5 tools; one-sentence descriptions; short verb names. Tool schemas always consume tokens; outputs add per call. If data is always required for a query class, prefetch into prompt instead of also registering a redundant tool.

**Single-turn**: Signal already creates a new `LanguageModelSession` per request in `FoundationModelsCoach.respond`. Refresh instructions from `Date()` each request.

**No Apple system clock tool**: expose wall clock via dynamic instructions and/or a custom zero-argument tool.

### Target design

#### 1. Clock anchor (required)

**A. Dynamic session instructions**

Add `CoachSessionFactory.makeInstructions(referenceDate:calendar:)`:

- All values from `Date()` at session creation. Never hardcode calendar days.
- Compact format via `CoachClockFormatter` (testable): dayKey, weekday, short time, timezone id.
- Persona rules stay concise (TN3193: imperative, short).
- Temporal semantics (one or two sentences):

```
Clock is the current device time. Health day YYYY-MM-DD lines describe that calendar day's data; they may include today when dayKey matches Clock. Only Clock and getDeviceClock define the current moment.
```

**B. `getDeviceClock` tool**

Zero-argument tool returning fresh `Date()` on each call (same format as instructions Clock line). For explicit "what time is it?" or when the model needs to re-verify mid-request.

Do not duplicate Clock in `assembledPrompt` unless Instruments profiling shows instructions are ignored.

#### 2. Fix misleading "today" labels (required)

- `DerivedMetricsService.computeProteinTarget`: fetch nutrition for `referenceDay = calendar.startOfDay(for: Date())` only. No latest-ever fallback.
- `CoachContextBuilder.formatDerivedMetrics`: emit protein line only when data is for referenceDay.
- Add health sync freshness line when latest DailyMetric is stale (see above).

#### 3. Calendar efficiency (required)

Apple pattern: Clock in instructions; calendar tool takes **dayKey range args** the model generates.

Refactor `CalendarScheduleTool`:

- Args: `fromDayKey`, `toDayKey` (YYYY-MM-DD)
- Fetch and format events in range

Prompt strategy (TN3193):

- Schedule-focused queries (`CoachQueryIntent.isScheduleFocused`): prefetch `calendarSummary` into prompt (pin during truncation).
- All other queries: omit `calendarSummary` from prompt; model uses `calendarSchedule` tool when needed.

#### 4. Smarter coach RAG (required)

Production `RAGRetriever` ignores `TemporalQueryParser`. Diagnostics has the correct path via `DiagnosticsRetrievalRunner` + `QueryRetrievalMode`.

Extract shared helper (e.g. `HealthVectorRetriever`) used by coach and Diagnostics:

1. `QueryRetrievalMode.resolve(in:referenceDate:calendar:)`
2. Embed + search with dayKey filters when temporal window detected
3. `DiagnosticsRetrieval.rankedNeighbors` for recency/temporal ranking
4. Return summaryText strings (coach k=4)

Pass `referenceDate: Date()` from `CoachContextBuilder.buildContext`.

Do not change Summarizer `Health day …` embedding format in this milestone.

#### 5. FM concurrency gate (required)

`FoundationModelsCoach` must use `FoundationModelsInferenceGate.shared` (same as `CalendarAlcoholFMClassifier`). One FM session at a time app-wide.

### Tool budget after milestone (4 tools)

| Tool | When | Args |
|------|------|------|
| `getDeviceClock` | Current date/time questions | none |
| `calendarSchedule` | Schedule when not in prompt | fromDayKey, toDayKey |
| `exerciseHistory` | Named lift history | exerciseName |
| `muscleVolume` | Volume/MEV/MRV | muscleName |

### Out of scope (M7+)

`readiness`, `metricTrend`, `nutritionTotals`, `semanticRecall`, `profileFact` tools. Multi-turn transcript. Summarizer format changes. MLX/cloud. Full sim test matrix.

### Files

| Area | Files |
|------|-------|
| Clock | NEW `CoachClockFormatter.swift`, NEW `DeviceClockTool.swift` |
| Session | `CoachSystemPrompt.swift`, `CoachSessionFactory` in same file |
| Coach | `FoundationModelsCoach.swift`, `CoachContextBuilder.swift` |
| RAG | `RAGRetriever.swift` or NEW `HealthVectorRetriever.swift` |
| Calendar | `CalendarScheduleTool.swift` |
| Metrics | `DerivedMetricsService.swift` |
| Tests | NEW `CoachClockFormatterTests.swift`, extend `CoachContextBuilderTests.swift` |

Agent-owned Xcode setup per `.cursor/rules/xcode-project-setup.mdc`. Prefer folder sync for new Swift under synced roots.

### Delicate constraints

1. One FM request at a time via shared gate + `isResponding`
2. Clock lives in instructions (survives prompt truncation / RAG drop retry)
3. `CoachQueryIntent` schedule pin unchanged for schedule queries
4. `SchedulingCalendar.make()` for coach date math
5. No em dashes in strings; no network at runtime
6. Do not break `CalendarAlcoholFMClassifier` gate behavior

### Verification

**Gate A (agent):** unit tests for `CoachClockFormatter`, protein referenceDay, temporal RAG wiring. Optional: `CoachContextBuilderTests` only. Do not run full sim suite unless asked.

**Gate B (device, required):** iPhone 16 Pro `id=00008140-001E34E10A01801C`. `build_device` → `install_app` → `launch_app`.

Manual checks:

1. "What day and time is it?" matches status bar
2. After today's workout/sync, RAG may show `Health day <today>`; coach must treat it as today's health data when dayKey matches Clock
3. When sync is stale (latest metric days old), coach cites freshness, does not call stale day "today"
4. "How did I sleep last week?" uses temporal RAG, not random old vectors
5. "What's on my calendar tomorrow?" correct events
6. No concurrent FM crash with calendar alcohol classifier

Append `AGENT-BUILD-UPDATES.md` on completion.
