# On-Device AI Health & Fitness Coach — Build Plan

## Context

Goal: a fully on-device, privacy-first iOS health and fitness coach for personal use on an iPhone 16 Pro (A18 Pro). It ingests Apple Health telemetry and Hevy workout history, normalizes it, stores it in a local vector database for retrieval-augmented generation (RAG), and uses Apple's on-device Foundation Models as the coaching brain. No health data leaves the device after initialization.

This plan is written to be executed by Composer 2.5 in Cursor, one version per Composer session, with commits between milestones. V1 and V2 are specified in full; V3 to V5 are roadmap outlines to be detailed once V1 proves out.

### Confirmed decisions
- **Apple Developer account:** active paid account. On-device builds, the increased-memory-limit entitlement, and HealthKit writes are all available from day one.
- **V1 scope:** foundational plumbing PLUS a working OLED dashboard rendering real recovery/HRV/RHR/sleep/energy metrics, so V1 is independently usable and verifiable before any LLM work.
- **LLM engine:** Apple Foundation Models framework (`LanguageModelSession`, `@Generable`, `Tool`) for generation, wrapped behind an `LLMCoach` protocol so MLX Swift can slot in later without rewrites.
- **Embedder:** EmbeddingGemma-300M via MLX Swift (SOTA on-device retrieval, 768-dim Matryoshka, 2K context), behind an `EmbeddingService` protocol with `NLContextualEmbedding` as a zero-dependency fallback. MLX Swift is therefore a core V1 dependency (and pre-positions a future MLX LLM swap).
- **Initial data:** real Apple Health `export.xml` and Hevy CSV exports will be provided and imported on day one.

### Hard platform requirements
- Deployment target iOS 26+, device iPhone 16 Pro (Apple Intelligence enabled).
- Entitlement `com.apple.developer.kernel.increased-memory-limit` (Jumbo mode, up to ~6 GB foreground).
- Capabilities: HealthKit, Background Modes (background delivery + background processing).

---

## Feasibility notes and deviations from the source research

Read these before building; they correct a few inaccuracies in the source document that would otherwise cause wasted work.

1. **HRV metric.** Apple Health exposes `heartRateVariabilitySDNN`, not rMSSD. rMSSD is not a native HealthKit type. All HRV baselines in this build use SDNN. The HRV4Training-style 60-day baseline vs 7-day acute with a 0.75 SD band (V3) is computed on SDNN.
2. **No on-device fine-tuning in the core path.** Foundation Models personalization is achieved through RAG context, not weight updates. Apple's adapter training is a Mac-side step, not on-device LoRA. On-device LoRA via MLX stays out of scope unless we later switch engines.
3. **Embedding initialization is on-device by default.** The source proposes a one-time cloud preprocessing step. Since the goal is privacy-first and the iPhone 16 Pro can handle it, V1 parses `export.xml` with a streaming parser and generates embeddings on-device via `NLContextualEmbedding`. Cloud preprocessing remains an optional fallback only if on-device import proves too slow on the full history.
4. **Foundation Models context window** is small (about 4k tokens per session in the current release). RAG and strict token budgeting are mandatory, exactly as the source states.
5. **Concurrency safety.** Never fire concurrent requests to a `LanguageModelSession`; bind UI to `isResponding`. Always call HealthKit `completionHandler` or background delivery gets throttled off permanently.

---

## Research-first protocol (read this before any API work)

Several frameworks in this build move fast (Foundation Models shipped in iOS 26 and is still evolving in 2026). Do not trust any API signature from memory, including the reference snippets below. They are a **starting point to orient from, not gospel** — some may already be stale.

For every milestone that touches Foundation Models, MLX/EmbeddingGemma, or HealthKit effort scoring, Composer must:

1. **Fetch the current canonical doc first.** Authoritative source URLs are listed per API below. Read the live signatures, not training memory. Apple docs render via JavaScript, so use Cursor's docs/web tooling or the `@Docs` feature pointed at these URLs; if a fetch returns empty, fall back to Xcode Quick Help and autocomplete on the real symbols.
2. **Let the compiler be the arbiter.** Write against the real symbols, build, and fix against actual compiler errors. Never paper over a "cannot find symbol" by inventing a plausible API.
3. **If a documented symbol does not exist in the installed SDK, STOP and report** (per the loop guardrails) rather than substituting a guess.

### Canonical sources to point Composer at

| Area | Source |
|---|---|
| Foundation Models (overview) | https://developer.apple.com/documentation/FoundationModels |
| LanguageModelSession | https://developer.apple.com/documentation/foundationmodels/languagemodelsession |
| Context window management | https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window |
| Generable / Guided generation | https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models |
| EmbeddingGemma (model + prompts) | https://ai.google.dev/gemma/docs/embeddinggemma and https://huggingface.co/google/embeddinggemma-300m |
| MLX Swift | https://github.com/ml-explore/mlx-swift and https://github.com/ml-explore/mlx-swift-examples |
| NLContextualEmbedding (fallback) | https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding |
| workoutEffortScore | https://developer.apple.com/documentation/healthkit (search HKQuantityType workoutEffortScore) |

### Verified constraints (confirmed June 2026 — design around these)

- **Context window: ~4,096 tokens per `LanguageModelSession`**, covering instructions + all prompts + all responses combined. RAG plus aggressive token budgeting is mandatory. Apple's TN3193 is the official guidance on pruning/summarizing the transcript; follow its recommended pattern rather than improvising.
- **Embedder is EmbeddingGemma-300M via MLX Swift** (architect's decision; see below). 768-dim native output (truncatable to 512/256/128 via Matryoshka), 2K-token context, state-of-the-art on-device retrieval quality. Store 768-dim vectors (or the chosen Matryoshka size) as `[Float]` in SwiftData. The 2K context means daily summaries do not need aggressive chunking. `NLContextualEmbedding` (512-dim, 256-token cap, native/zero-dependency) is the documented fallback only if MLX integration proves troublesome.
- **Vector store is pure-Swift brute-force cosine over SwiftData-stored vectors** (Accelerate/vDSP). Decided during the build: at a ~3-4k vector personal corpus, HNSW (ObjectBox) is over-specified and added codegen friction. Brute force is sub-millisecond at this scale. Kept behind the `VectorStore` protocol so ObjectBox/HNSW can be added if the corpus ever reaches the hundreds of thousands.
- **One in-flight request per session.** A second `respond`/`streamResponse` call before the first completes throws at runtime. Gate strictly on `isResponding`.

### Reference snippets (orient only — verify against the sources above before relying on them)

### Foundation Models framework (V2, entire LLM path — complete blind spot)

Paste into the V2 M4 and M6 milestone prompts verbatim:

```
// FOUNDATION MODELS — iOS 26+, import FoundationModels
// LanguageModelSession
let session = LanguageModelSession(
    model: SystemLanguageModel.default,
    instructions: "Your system prompt here"
)
// Streaming response
for try await chunk in session.streamResponse(to: prompt) { ... }
// Prewarm (call on view appear, async)
await session.prewarm()
// Concurrency gate — never send while true
session.isResponding: Bool

// Structured output — mark struct with @Generable
@Generable struct WorkoutRecommendation {
    @Guide(.anyOf(["Light", "Moderate", "Maximum Effort"])) var intensity: String
    var rationale: String
    var targetRPE: Int
}
let result: WorkoutRecommendation = try await session.respond(
    to: prompt,
    generating: WorkoutRecommendation.self
)

// Tool calling
struct CalendarTool: Tool {
    let name = "fetchCalendarEvents"
    let description = "Returns calendar events for a given date range"
    func call(arguments: CalendarTool.Arguments) async throws -> ToolOutput { ... }
    @Generable struct Arguments { var startDate: String; var endDate: String }
}
let session = LanguageModelSession(tools: [CalendarTool()])

// Error handling
do {
    ...
} catch LanguageModelSession.GenerationError.exceededContextWindowSize {
    // truncate oldest RAG context, retry
} catch LanguageModelSession.GenerationError.rateLimited {
    // backoff, surface tooltip
}
```

### Pure-Swift vector store (V1 M2 — no third-party dependency)

Store vectors in SwiftData and rank with Accelerate. Orientation only:

```
import SwiftData
import Accelerate

@Model final class HealthVector {
    var dayKey: String
    var metricKind: String
    var summaryText: String
    var vector: [Float]          // 768-dim (EmbeddingGemma)
    init(dayKey: String, metricKind: String, summaryText: String, vector: [Float]) {
        self.dayKey = dayKey; self.metricKind = metricKind
        self.summaryText = summaryText; self.vector = vector
    }
}

// Cosine similarity via vDSP; fetch all, score, take top-k.
func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
    vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
    vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
    return dot / (sqrt(na) * sqrt(nb) + 1e-8)
}
// nearestNeighbors: context.fetch(FetchDescriptor<HealthVector>()), map to (cosine, row),
// sort desc, prefix(k). Sub-millisecond at a few thousand rows.
```

### EmbeddingGemma via MLX Swift (V1 M3 — primary embedder; research the current integration path)

Verified facts (June 2026): 308M params, 768-dim output truncatable to 512/256/128 (Matryoshka), 2K-token context, SOTA on-device retrieval. Runs under ~200MB RAM quantized. Apple's MLX Swift is the supported on-device runtime. Do NOT hardcode the MLX API from this note; read the current mlx-swift-examples embeddings path and the EmbeddingGemma model card, then build and compiler-verify.

Critical retrieval detail: EmbeddingGemma uses **task-specific prompt prefixes**. Documents and queries must be embedded with different templates (per the model card), e.g. a retrieval document prefix vs a `task: search result | query:` prefix. Getting this wrong silently degrades retrieval. The `EmbeddingService.embed(_:kind:)` API exists precisely to enforce this split.

Orientation only (verify every symbol against the canonical sources):
```
// Pseudostructure — actual MLX Swift embedding API must be confirmed against mlx-swift-examples
let model = try await EmbeddingGemma.load(weightsURL: bundledOrDownloadedURL)   // confirm loader API
func embed(_ text: String, kind: EmbeddingKind) -> [Float] {
    let prompted = kind.promptPrefix + text   // document vs query template from the model card
    let raw = model.encode(prompted)          // confirm encode/pooling API
    return matryoshkaTruncate(raw, to: 768)   // 768 default; tunable to 512/256/128
}
```

**Fallback (only if MLX stalls V1):** `NLContextualEmbedding` (native, zero-dependency, 512-dim, 256-token cap). Same `EmbeddingService` protocol, switchable by one flag. If used, mean-pool per-token vectors and keep each summary under 256 tokens. This is the contingency, not the plan.

### HKQuantityTypeIdentifier.workoutEffortScore (V2 M3 — iOS 18, edge of training)

Paste into V2 M3 milestone prompt:

```
// workoutEffortScore — iOS 18+, watchOS 11+
// Write via HKWorkoutBuilder after finishing a session
let effortType = HKQuantityType(.workoutEffortScore)
let effortQuantity = HKQuantity(unit: .appleEffortScore(), doubleValue: calculatedScore) // 0.0–10.0
let effortSample = HKQuantitySample(
    type: effortType,
    quantity: effortQuantity,
    start: workoutStart,
    end: workoutEnd
)
try await builder.addSamples([effortSample])
try await builder.finishWorkout()
```

---

## Agent build environment, tooling, and verification loop

Distilled from current (2026) practice for shipping native Apple apps with coding agents. The agent's hard part is not writing Swift; it is the build/verify loop and Xcode-managed files. Set this up before M1.

### MCP servers (configure in Cursor before starting)
- **XcodeBuildMCP** (headless build/test/sim/LLDB). Gives Composer `build_sim`, `build_device`, `test_sim`, `list_sims`, `boot_sim`, `screenshot`, and LLDB tools (`debug_attach_sim`, `debug_variables`, `debug_eval`). These return **structured JSON errors by file and line**, which is what lets the agent close a write -> build -> read-error -> fix loop without a human. Install via `npx -y xcodebuildmcp@latest mcp` (add through Cursor's MCP settings).
- **Apple Xcode MCP** (requires a running Xcode): documentation search, Swift REPL, SwiftUI preview rendering, real-time diagnostics. Its **documentation search is the primary tool for the research-first protocol** above (it reads the current Foundation Models / HealthKit docs that JS-rendered web fetches cannot).
- Rule for Composer: prefer MCP tools over raw `xcodebuild`; MCP returns structured JSON, Bash returns unstructured text.

### Build loop
- Agent iterates on the **iOS 26 Simulator (iPhone 16 Pro)** for compile and UI-correctness loops with mock/sample data.
- The **physical iPhone 16 Pro is required for HealthKit real data, the increased-memory-limit entitlement, background delivery, and Foundation Models verification** (these are the human-run device checks in the Verification section).
- Document the exact build invocation so the agent can fall back if MCP is down:
  ```
  xcodebuild -scheme Signal -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
  xcodebuild -scheme Signal -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
  ```

### Protect Xcode-managed files (hooks)
- **Block agent edits to `.pbxproj`, `.xcodeproj/`, `.xcworkspace/`, `.entitlements`, `.xib`, `.storyboard`.** The agent creates Swift files; you add them to targets and manage signing/capabilities/entitlements through the Xcode UI (a 5-second manual step that prevents hours of project-corruption recovery). The increased-memory-limit entitlement and all capabilities from M1 are therefore configured by you in Xcode, not by the agent.
- Run `swiftformat` on every Swift file write (PostToolUse hook) for consistent formatting.

### Modern Swift patterns to enforce (agents regress to deprecated training-data patterns)
- `@Observable` macro, never `ObservableObject`/`@Published`.
- `NavigationStack` + `navigationDestination(for:)`, never `NavigationView`.
- All view models `@MainActor`; Swift 6 strict concurrency; `async/await` exclusively; value types `Sendable` for cross-actor transfer.
- Refactor large SwiftUI views into smaller subviews/expressions to avoid "unable to type-check in reasonable time" errors.
- HealthKit: always check `HKHealthStore.isHealthDataAvailable()` and never assume authorization. SwiftData: `@Query` in views, `modelContext.fetch()` elsewhere; document `.cascade`/`.nullify` deletion rules to avoid orphaned data.

### Verification reality
- The agent can confirm a screen renders and does not crash (`screenshot`, `RenderPreview`), and can run unit tests for logic. It **cannot judge layout, color accuracy, or visual polish** (OLED black correctness, chart legibility) or validate real HealthKit/Foundation Models behavior. Those stay human-verified on device, as captured in the Verification section.
- Lean on unit tests as the agent's autonomous feedback substitute wherever UI interaction would otherwise be needed (recovery math, summarizer token budget, RAG retrieval ranking, importer counts).

## Running in Composer 2.5: the three risks, accounted for

Composer 2.5 (released May 2026) is built on the Kimi K2.5 base (late-2025/early-2026 cutoff) with heavy Cursor post-training. It is strong at long, instruction-heavy tasks and cheap to run. The three failure modes for this specific build and their mitigations:

### Risk 1 — stale training data on the newest APIs
iOS 26, Foundation Models, and EmbeddingGemma all sit right at the model's training edge: partially known, which is the worst case (confident but possibly wrong signatures). Mitigation is the research-first protocol, enforced two ways:
- The `.cursorrules` research-first block forbids trusting memory for these APIs.
- Live docs are pre-indexed (Risk 2) so the agent has an authoritative source to check against.

### Risk 2 — live documentation access (this is what JS-rendered Apple docs broke)
Use Cursor's native mechanisms, in order:
1. **`@Docs` (primary).** Before starting, add each canonical URL from the research-first source table as an indexed doc (Settings -> Docs -> Add new doc, point at the root). Cursor's crawler indexes the subpages **server-side**, which gets around the JavaScript rendering that defeats raw fetches. The agent then vector-searches the indexed docs. Index at minimum: Foundation Models, LanguageModelSession, TN3193, EmbeddingGemma model card, MLX Swift examples.
2. **`@Web` (secondary).** On-the-fly search for anything not pre-indexed.
3. **Apple Xcode MCP doc search (tertiary).** Reads installed-SDK docs and Quick Help directly.
- In each milestone prompt, explicitly reference the indexed doc, e.g. "Use @Docs FoundationModels to confirm the current LanguageModelSession API before writing."

### Risk 3 — runaway query cost
Composer 2.5 pricing (June 2026): Standard $0.50/M input, $2.50/M output; Fast $3/M input, $15/M output. This is roughly a tenth of frontier-model rates, so the "huge incident bill" scenario comes from unbounded loops and oversized context, not per-token price. Controls already in the plan:
- **One milestone per session, commit, then clear context.** Context size is the dominant cost driver; do not let a session accumulate the whole codebase.
- **Stop after 2 failed builds** (`.cursorrules`), so a broken loop cannot burn tokens indefinitely.
- **Use Standard tier for bulk implementation; reserve Fast tier for interactive debugging.** Auto mode on Pro does not draw from the credit pool.
- **File-purpose annotations** (in the repo layout below and in `.cursorrules`) so the agent opens the right file instead of reading everything.
- Realistic envelope: a scoped milestone is cents to low dollars; V1 end to end with retries is single-digit to low-tens of dollars, within the Pro ($20/mo) plan. Ultra ($200/mo) is unnecessary for one personal app.

## Repository layout

```
HealthCoach/
  HealthCoach.xcodeproj
  HealthCoach/
    App/                  HealthCoachApp.swift, AppEnvironment.swift
    Core/
      Logging/            Log.swift (os.Logger categories)
      Memory/             MemoryEntitlement notes, model lifecycle helpers
    Data/
      Models/             SwiftData models (DailyMetric, RecoverySnapshot; V2: workouts/foods)
      VectorStore/        VectorStore.swift (protocol) + SwiftDataVectorStore (brute-force cosine via Accelerate)
      Embedding/          EmbeddingService.swift (protocol) + GemmaEmbeddingService (MLX) + NLEmbeddingService (fallback)
      Normalization/      DailySummary.swift (MCP-style JSON schema) + Summarizer
    Health/
      HealthKitManager.swift
      HealthKitBackground.swift   (observer queries, protectedData handling)
      Importers/                  AppleHealthXMLImporter.swift, HevyCSVImporter.swift
    Analytics/
      RecoveryEngine.swift        (V1 simple baselines; V3 rigorous SD-band math)
    Features/
      Dashboard/          DashboardView.swift + cards + Swift Charts
      Debug/              DiagnosticsView.swift
    Coach/                (V2) LLMCoach.swift protocol, FoundationModelsCoach.swift, RAGRetriever.swift, ChatView.swift
    Resources/            Assets, OLED color tokens
  HealthCoachWatch/       (V3+) watchOS companion target
  .cursorrules
```

`.cursorrules` (create first) should pin: iOS 26 target, SwiftUI + SwiftData + MLX Swift (the only approved third-party dep), `os.Logger` in every data path, no em/en dashes in code or copy, no concurrent LLM calls, always call HealthKit completion handlers, one version scope per session, do not refactor stable code from prior versions, and a research-first rule: read current official docs for fast-moving APIs (Foundation Models, MLX/EmbeddingGemma) rather than trusting training memory, and stop rather than invent a signature.

---

## App identity

**Name:** Signal
**Tagline:** Your body's signals, decoded.
**Bundle ID:** `com.cameronro.signal` (or adjust to your prefix)

---

## iOS assets and app polish

This section covers everything Xcode needs beyond code. Most of it belongs in M1 of each version; widget and notification assets belong in the version that introduces the feature.

### App icon
- Single master artwork: 1024x1024 PNG, no alpha channel, no rounded corners (Xcode applies the squircle mask).
- Design direction: a clean waveform or EKG-style signal line on a deep background, minimal, no gradients. Must read at 60x60 (the Home Screen size). Provide only the 1024x1024; Xcode generates all required sizes automatically via the single-size icon set (`AppIcon.appiconset` with `preserves-vector-representation: false`).
- iOS 18+ supports a **dark icon variant** and a **tinted icon variant**. Supply all three: light (default), dark (white/light waveform on near-black), tinted (monochrome for the system to colorize). Add as alternate appearances in the asset catalog.
- No text in the icon.

### Launch screen
- Use the `UILaunchScreen` Info.plist key approach (no storyboard). Set `UIColorName` to the OLED black token and `UIImageName` to a centered wordmark or the icon glyph. This is the lightest, storyboard-free path and Apple's current recommendation.

### Color system (`Resources/Colors.xcassets`)
Define semantic named colors used everywhere in SwiftUI via `Color("token")`:

| Token | Light | Dark |
|---|---|---|
| `Background` | white | `#000000` (true OLED black) |
| `Surface` | `#F2F2F7` (system grouped) | `#1C1C1E` |
| `SurfaceElevated` | white | `#2C2C2E` |
| `Primary` | `#007AFF` (system blue) | same |
| `Positive` | `#34C759` (system green) | same |
| `Warning` | `#FF9F0A` (system orange) | same |
| `Negative` | `#FF453A` (system red) | same |
| `TextPrimary` | `#000000` | `#FFFFFF` |
| `TextSecondary` | `#3C3C43` at 60% | `#EBEBF5` at 60% |

All cards use `Surface` for their background, not a hardcoded value.

### Typography
Use `Font.system` with `.design(.rounded)` throughout for a modern, athletic feel. Define a small type scale as static `Font` extensions in `Resources/Typography.swift`:
- `.displayLarge` — `.largeTitle.weight(.bold).design(.rounded)`
- `.metricValue` — `.system(size: 44, weight: .semibold, design: .rounded)` (for HRV, RHR numbers on dashboard cards)
- `.cardLabel` — `.subheadline.weight(.medium)`
- `.caption` — `.caption2`

### SF Symbols
Standardize icon usage. Define a `Symbol` enum in `Resources/Symbols.swift` mapping semantic names to SF Symbol strings, so icon choices are not scattered across views:
- `heart.variability`: `heart.rate` or `waveform.path.ecg`
- `recovery`: `bolt.heart`
- `sleep`: `bed.double`
- `energy`: `flame`
- `workout`: `dumbbell`
- `coach`: `brain.head.profile`

Use `.symbolRenderingMode(.hierarchical)` with `Primary` color by default.

### Notification assets
V1 does not push notifications. V3 introduces the morning briefing. When that milestone lands: add a `UNNotificationCategory` identifier `daily_briefing` and register it in the app delegate. No banner image is required for local notifications.

### Widget (future, V3+)
A Lock Screen widget showing today's recovery score. Placeholder: add an empty `WidgetKit` extension target in M1 named `SignalWidget` but do not implement it yet. Having the target present from day one avoids a scheme reconfiguration later.

### App Store metadata (personal build, skip for now)
Since this is a personal sideload, no App Store submission is planned. Skip privacy nutrition labels, App Review notes, and TestFlight configuration unless explicitly added to a future version.

---

## Version 1 — MVP core, storage, ingestion, dashboard

Each milestone below is a discrete Composer task with its own acceptance check. Commit after each.

### M1. Project skeleton, entitlements, and app identity
**Human (Xcode UI, not the agent — these touch protected project files):**
- Create SwiftUI app named **Signal**, iOS 26 target, bundle id `com.cameronro.signal`, on a real device run scheme.
- Add capabilities: HealthKit, Background Modes (Background fetch / Background processing + HealthKit background delivery).
- Add entitlement `com.apple.developer.kernel.increased-memory-limit`.
- Add `Info.plist` keys: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, and `UILaunchScreen` with the OLED black background token.
- Add the SPM dependency (MLX Swift) and the empty `SignalWidget` target. (ObjectBox dropped; vector store is pure-Swift in SwiftData.)
- Add each new Swift file the agent creates to the correct target as it goes.

**Agent (Swift source only):**
- `Core/Logging/Log.swift`: `os.Logger` with categories `healthkit`, `import`, `vectorstore`, `embedding`, `sync`, `ui`, `recovery`.
- `Resources/Colors.xcassets`: add all named color tokens from the iOS assets section above. Set the Xcode global accent color to `Primary`.
- `Resources/Typography.swift`: define the type scale as static `Font` extensions.
- `Resources/Symbols.swift`: define the `Symbol` enum mapping semantic names to SF Symbol strings.
- App icon: author the `AppIcon.appiconset` Contents.json with a 1024x1024 placeholder (solid `#000000` with a white waveform glyph is fine for now), including dark and tinted variant slots to avoid asset catalog warnings. (Human adds the catalog to the target if needed.)
- The empty `SignalWidget` target is created by the human above; the agent leaves it untouched until V3.
- **Accept:** builds and launches on device; true OLED black launch screen visible; logs confirm entitlement-backed memory headroom; HealthKit capability present; no asset catalog warnings.

### M2. Storage layer
- SwiftData models:
  - `DailyMetric` { date (unique day key), hrvSDNN_ms?, restingHR?, activeEnergy_kcal?, sleepHours?, source }
  - `RecoverySnapshot` { date, recoveryScore, hrvBaseline, hrvAcute, notes }
  - Persisted sync anchors store (`SyncAnchorStore`) keyed by HK type.
- Vector store is **pure-Swift brute-force** (decided during the build: ObjectBox/HNSW is over-specified for a ~3-4k vector personal corpus and added codegen friction). SwiftData model `HealthVector` { dayKey (date), metricKind, summaryText, vector: [Float] (768-dim) }.
- `VectorStore.swift` behind a protocol: `insert`, `upsert(dayKey:metricKind:...)`, `nearestNeighbors(query:[Float], k:Int)`, `count`, `deleteAll`. `nearestNeighbors` fetches all vectors and computes cosine similarity with Accelerate (`vDSP`), returns top-k. Sub-millisecond at a few thousand vectors. Protocol leaves room to swap in ObjectBox/HNSW if the corpus ever reaches the hundreds of thousands.
- **Accept:** unit harness inserts sample vectors and `nearestNeighbors` ranks the matching one first; query latency under a frame budget; counts visible in Diagnostics (M9).

### M3. Embedding service (EmbeddingGemma via MLX Swift)
- Add MLX Swift + an MLX embeddings helper (mlx-swift-examples or an embeddings community package) via SPM. Research the current robust path against the canonical sources before wiring it.
- Bundle or first-launch-download the quantized `google/embeddinggemma-300m` weights (4-bit safetensors). Treat the download as a one-time setup step with progress UI; cache to Application Support.
- `EmbeddingService.swift`: a single protocol-fronted service exposing `embed(_ text: String, kind: EmbeddingKind) -> [Float]` and `embedBatch`. `EmbeddingKind` distinguishes `.document` vs `.query` so the correct EmbeddingGemma task prompt prefix is applied (retrieval quality depends on this: documents and queries use different prompt templates per the model card). Output 768-dim (or chosen Matryoshka size); record the dimension and use it as the `HealthVector` vector length.
- Keep `NLContextualEmbedding` behind the same protocol as a fallback `EmbeddingService` implementation, switchable by a single flag, in case MLX integration stalls V1.
- **Accept:** embedding a known string returns a stable, correctly-sized vector; a query embedding retrieves its matching document with markedly higher cosine similarity than an unrelated one; the document-vs-query prompt prefixes are applied correctly.

### M4. Normalization layer (MCP-style schema)
- `DailySummary` Codable struct: the clean uniform schema (date, hrvSDNN, restingHR, activeEnergy, sleepHours, workouts summary, computed recoveryScore).
- `Summarizer`: turns a `DailyMetric` (+ that day's workouts once V2 lands) into (a) the JSON `DailySummary` and (b) a compact natural-language text summary used for embedding. Keep the text dense and uniform so retrieval is consistent.
- EmbeddingGemma's 2K-token context comfortably fits a full day (metrics plus workouts) in one summary, so no per-day chunking is needed. Keep summaries dense regardless, for retrieval precision and token budget at generation time. (If the `NLContextualEmbedding` fallback is ever used, its 256-token cap reintroduces the need to split a heavy day into multiple `HealthVector` rows sharing a `dayKey`.)
- **Accept:** a `DailyMetric` round-trips to JSON and to a one-paragraph summary string; snapshot test on format stability.

### M5. Apple Health XML importer (one-time historical)
- `AppleHealthXMLImporter.swift`: streaming `XMLParser` (the export is often hundreds of MB; never load it whole). Filter to Tier 1 types only (HRV SDNN, RestingHR, ActiveEnergy, SleepAnalysis, HeartRate); discard noise.
- Aggregate records into per-day `DailyMetric` rows, upsert into SwiftData, then `Summarizer` to text, `EmbeddingService.embedBatch`, store in the vector store.
- Progress reporting + cancellation; chunked/batched writes; full os.Logger coverage of counts and timings.
- Import entry point: a settings/onboarding screen with a document picker to select the `export.zip`/`export.xml`.
- **Accept:** importing the real export populates SwiftData day rows and vector rows with matching counts; no OOM; progress completes.

### M6. Hevy CSV importer (structured, revised during build)
- **Decision (made during the build):** store workouts **structurally**, not as lossy text. The first pass flattened sets (e.g. "24kg x 10" for what was 3 sets of 10 @ 24kg at RPE 8/8.5/9), which destroys the set/rep/weight/RPE structure a strength coach needs. V2's workout STORAGE models are pulled forward into V1 (storage only, not the logging UI, which stays in V2).
- The Hevy CSV is one row per set. Columns: `title`, `start_time` ("31 May 2026, 17:53"), `end_time`, `description`, `exercise_title`, `superset_id`, `exercise_notes`, `set_index`, `set_type` (warmup|normal), `weight_kg`, `reps`, `distance_km`, `duration_seconds`, `rpe`.
- `HevyCSVImporter.swift`: parse and persist EVERY column into SwiftData models (source of truth, lossless):
  - `WorkoutSession` { title, sessionDescription, startTime, endTime, date (start of day) }
  - `WorkoutExercise` { exerciseTitle, notes, supersetId, order } belongs to session
  - `SetEntry` { setIndex, setType, weightKg?, reps?, distanceKm?, durationSeconds?, rpe? } belongs to exercise
  - Group per-set rows into session -> exercise -> sets. RPE/distance/duration/notes/superset often empty: store nil cleanly. Idempotent: upsert `WorkoutSession` by (title + startTime).
- The `Summarizer` renders a **faithful** workout summary from the structured data for that day's embedding text (derived; structured rows are source of truth): group by exercise, keep warmups distinct, compress identical working sets as "N x reps @ weightkg" (never drop the set count), list varied reps as "weightkg x r1/r2/r3", include RPE range and notes. Target example: "Seated Incline Curl (Dumbbell): 3 x 10 @ 24kg (RPE 8 to 9)". Re-embed (`.document`) and `VectorStore.upsert` affected days.
- Distinct "Import Hevy CSV" entry point in the UI (separate from the Health import). Input is the extracted `.csv` (user unzips `HevyExport.zip` in Files).
- **Accept:** the example (3 sets, 24kg, 10 reps, RPE 8/8.5/9) round-trips to 3 `SetEntry` rows AND renders "3 x 10 @ 24kg (RPE 8 to 9)"; Hevy sessions land on the right days; re-import leaves counts unchanged; spot-checked day summaries show full set detail.

### M7. HealthKit live pipeline
- `HealthKitManager.swift`: request read authorization for Tier 1 types. Use `HKAnchoredObjectQuery` for delta reads; persist anchors in `SyncAnchorStore`.
- `processDelta()`: pull new samples since anchor, upsert `DailyMetric`, re-summarize affected days, re-embed, update the vector store.
- **Accept:** after granting auth, a foreground sync ingests recent days and updates the store incrementally (anchors advance, no duplication).

### M8. Background delivery + locked-device safety
- `HealthKitBackground.swift`: `HKObserverQuery` + `enableBackgroundDelivery` for Tier 1 types. The observer ONLY sets a lightweight "data is dirty" flag and immediately calls the provided `completionHandler` (critical: skipping this triggers iOS back-off and permanent loss of background delivery).
- Observe `UIApplication.protectedDataDidBecomeAvailableNotification` and app foregrounding: when fired and the dirty flag is set, run `processDelta()` against the now-decrypted store.
- **Accept:** logs show observer firing and completion handler called every time; heavy processing happens only after unlock/foreground; no crashes when woken while locked.

### M9. Recovery engine (V1 simple) + dashboard
- `RecoveryEngine.swift` (V1 simple version): rolling 7/30/60-day means for HRV SDNN and RHR; a basic recovery indicator (today vs recent baseline). The rigorous 60-day vs 7-day 0.75 SD-band model is deferred to V3 as planned.
- `DashboardView.swift` (SwiftUI): cards for Recovery, HRV trend, Resting HR, Active Energy, Sleep, using Swift Charts sparklines (7/30/60 toggle). Pull-to-refresh triggers `processDelta()`.
- Theming: true OLED black dark mode (`Color.black`, not system dark gray) plus a clean light mode; centralized color tokens in `Resources`.
- **Accept:** dashboard renders real imported + live metrics with charts; OLED dark and light both correct; pull-to-refresh updates values.

### M10. Diagnostics + RAG smoke test
- `DiagnosticsView.swift`: counts (DailyMetric rows, HealthVector count, last anchor per type, last sync time, last import summary), plus a manual "ask the store" box that embeds a typed query and shows top-k retrieved daily summaries (proves the RAG retrieval path before any LLM exists).
- **Accept:** typing "how did I sleep last week" or "hard leg days" returns sensibly relevant daily summaries.

### V1 Definition of Done
On-device app that: launches with increased memory, imports real Apple Health + Hevy history into SwiftData (structured rows plus a pure-Swift brute-force vector store), keeps itself current via anchored + background HealthKit sync with correct locked-device handling, computes simple recovery baselines, renders a true-OLED dashboard with charts, and proves retrieval relevance via the diagnostics query box. No cloud dependency at runtime.

---

## Version 2 — Workout logging UI + LLM coaching foundation

### M1. Workout schema additions (storage moved to V1 M6)
- The core workout storage models (`WorkoutSession`, `WorkoutExercise`, `SetEntry`) were pulled forward into V1 M6 to preserve Hevy import fidelity. V2 only ADDS what the logging UI needs on top:
  - `Exercise` catalog (name, primary muscle, equipment, isCustom), seeded/deduped from the distinct `exerciseTitle` values already imported in V1 (115 distinct).
  - `Routine`, `RoutineExercise` (order, target sets/reps) for templated sessions.
  - Link live-logged sessions to the catalog `Exercise` rather than a free-text title.
- No re-import needed; V1 already holds the structured history.

### M2. Hevy-style logging UI
- Routine list + start session, in-session screen with add-exercise, per-set weight/reps/RPE entry, mark-set-complete, and a manual rest timer (dynamic auto-extension is V4). Compact, glanceable, gym-friendly layout; OLED dark.
- Persist live to SwiftData; on finish, fold the session into that day's `DailySummary`, re-embed, update the vector store (reuse V1 Summarizer + EmbeddingService).

### M3. HealthKit workout write + Training Load
- On session completion, build an `HKWorkout` via `HKWorkoutBuilder` and write a calculated `HKQuantityTypeIdentifier.workoutEffortScore` (0 to 10, iOS 18+) so manual lifting influences Apple's native Training Load graphs.
- **Accept:** finished sessions appear in Apple Health with an effort score.

### M4. LLM coach abstraction + Foundation Models
- `LLMCoach` protocol (so MLX can be swapped later): `prewarm()`, `respond(to:context:) -> AsyncStream`, structured-output variants.
- `FoundationModelsCoach.swift`: `LanguageModelSession` with a strict system-prompt persona ("elite sports physiologist and strength coach; focus only on biomechanics, growth, recovery; ignore unrelated general knowledge").
- Structured outputs via `@Generable` (e.g., `WorkoutRecommendation`, `MacroEstimate` later) and `@Guide` constraints (e.g., intensity `.anyOf(["Light","Moderate","Maximum Effort"])`).

### M5. RAG retrieval into the prompt
- `RAGRetriever.swift`: embed the user query (EmbeddingService), `VectorStore.nearestNeighbors` for top-k daily summaries, assemble prompt within a strict token budget that respects the ~4k context window. Include the most recent N days plus the top retrieved historical days.

### M6. Chat UI + robustness
- `ChatView.swift`: call `session.prewarm(...)` on appear; bind submit button to `isResponding` (never fire concurrent requests); stream tokens.
- Wrap all generation in do/catch for `LanguageModelSession.GenerationError.exceededContextWindowSize` (auto-truncate oldest retrieved context and retry) and `rateLimited` (backoff + user-facing tooltip). Surface errors as helpful inline tooltips, not crashes.

### V2 Definition of Done
Full Hevy-style logging persisting to SwiftData and writing effort scores to Apple Health; a working on-device chat coach that retrieves real RAG context from the V1 vector store, answers within the context window, returns validated structured recommendations, and degrades gracefully on context-overflow and rate-limit errors with no concurrent-call crashes.

---

## Version 3 to 5 — roadmap outlines (detail after V1/V2 land)

### V3 — Proactive math + watchOS basics
- Replace V1 simple baselines with the rigorous model: 60-day SDNN baseline vs 7-day acute moving average, 0.75 SD band to classify normal fluctuation vs overtraining/deload signal. Athlytic-style exertion using 30-day max HR and 60-day resting HR.
- watchOS companion target; opportunistic sync via `WCSession.transferUserInfo` (battery-friendly).
- Contextual Daily Briefing as a morning local push built from the prior night's HRV.

### V4 — Live telemetry + calendar
- watchOS `HKWorkoutSession` + `HKLiveWorkoutBuilder` for continuous sensor polling during workouts.
- Active streaming via `WCSession.sendMessage` only during live coaching; downgrade to `transferUserInfo` otherwise.
- Dynamic rest timer: extend baseline rest by 10% on a detected cardiovascular spike (for example +15 bpm).
- `GoogleCalendarTool` via the Foundation Models `Tool` protocol so the coach can shift heavy days around busy calendar events.

### V5 — Dietary vision + sensory polish
- Local Vision-Language meal analysis (MLX Swift vision model) with the "Camera + Note" UX (photo + speech-to-text context fused for macro estimation).
- Dual-layer food data: grams in SQLite/SwiftData for thermodynamic accuracy, "Smart Serving Units" in the UI.
- Duolingo-style encouraging haptics (`UIImpactFeedbackGenerator` / CoreHaptics) on milestones.

---

## Composer 2.5 / Cursor execution guidance

- One version per Composer session; within a version, one milestone per task. Commit between milestones so context stays small and stable code is not rewritten.
- Keep `.cursorrules` (above) loaded so constraints (token budgets, completion handlers, no concurrent LLM calls, no em/en dashes) are always in scope.
- Lean on the `os.Logger` output: every data-path milestone must log counts and timings so Composer can self-diagnose loops from terminal output.
- Do not let the agent introduce cloud calls at runtime, automatic gyroscope rep tracking, or fine-tuning; those are explicitly out of scope.

---

## Verification

- **Build/run:** real iPhone 16 Pro, Debug scheme. Confirm entitlement-backed memory and no Jetsam termination during the full XML import.
- **V1 ingestion:** import the provided Apple Health export and Hevy CSV; in Diagnostics confirm `DailyMetric` count, `HealthVector` count, and per-type anchors are populated and consistent. Run the diagnostics RAG query box and confirm retrieved summaries are relevant.
- **V1 sync/background:** add a fresh Health sample, lock the phone, unlock, and confirm via logs that the observer fired, the completion handler was called, the dirty flag was set, and `processDelta()` ran on unlock with anchors advancing and no duplicate days.
- **V1 dashboard:** verify charts render real data in both true-OLED dark and light; pull-to-refresh updates values.
- **V2 logging:** log a session, finish it, confirm it persists in SwiftData and appears in Apple Health with a `workoutEffortScore`.
- **V2 coach:** ask a question whose answer requires history; confirm RAG retrieval pulls the right days, the response stays within the context window, structured outputs validate, the submit button is disabled while `isResponding`, and forcing a context overflow triggers the truncate-and-retry path rather than a crash.
