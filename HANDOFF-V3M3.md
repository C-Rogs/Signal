# Signal — Architect Handoff to Composer 2.5
## Session: V3 M3 — watchOS Companion UI

---

## Your role

You are implementing a single milestone of a personal iOS health coach app called Signal. You
receive a fully scoped task below. Do not refactor stable code from prior milestones unless
a file explicitly needs to change for this milestone. Commit when done.

---

## Hard constraints (non-negotiable)

- **Swift 6 strict concurrency.** All actors, @MainActor view models, Sendable value types.
- **@Observable macro only.** Never ObservableObject / @Published.
- **NavigationStack + navigationDestination(for:).** Never NavigationView.
- **No em dashes, en dashes, or double dashes** in any string, comment, or copy.
- **Xcode project:** `.cursor/rules/xcode-project-setup.mdc`. Prefer folder sync; edit `project.pbxproj` only when build requires it.
- **os.Logger in every data path.** Category: `"watch"` for WCSession code.
- **No cloud calls at runtime.** Everything is on-device / local network (WCSession).
- **Stop after 2 failed builds.** Report the exact compiler error rather than guessing.
- **Research-first for fast-moving APIs.** Verify WCSession / WKExtension / WidgetKit APIs
  via Xcode Quick Help or @Docs before writing. Do not invent signatures.

---

## Project identity

- **App name:** Signal
- **iOS bundle ID:** `com.cameronro.Signal` (capital S)
- **Watch bundle ID:** `com.cameronro.Signal.watchkitapp`
- **Repo root:** `/Users/cameronro/Development/Signal/`
- **iOS source root:** `Signal/Signal/Signal/`
- **Watch source root:** `Signal/Signal/SignalWatch Watch App/`
- **Tests:** `Signal/Signal/SignalTests/`

**Folder sync rule:** `Signal/Signal/Signal/`, `Signal/Signal/SignalTests/`, and `Signal/Signal/SignalWatch Watch App/` use Xcode folder sync. New `.swift` files under those roots compile automatically. If `build_device` fails on target membership, edit `project.pbxproj` per `.cursor/rules/xcode-project-setup.mdc`. Put iOS-side WCSession code under `Signal/Signal/Signal/Data/Watch/`. Watch-side changes go in `Signal/Signal/SignalWatch Watch App/`.

---

## State of the codebase entering this session

### Completed (do not rewrite)

**V1:** SwiftData storage, HealthKit live pipeline, background delivery, recovery engine (rolling
means), OLED dashboard with Swift Charts, RAG vector store (EmbeddingGemma / brute-force cosine),
Hevy CSV importer, Apple Health XML importer, DiagnosticsView.

**V2 M0–M8:** TabView shell (Dashboard / Train / Coach / Profile), exercise catalog with muscle
model, Hevy-grade logging UI (previous-set autofill, rest timers, supersets, set types),
HealthKit workout write + workoutEffortScore, in-session cue engine (CueEngine with 8 tiers,
hash-rotated variant pools, SetCueBannerView), set timestamps (startedAt / completedAt on
SetEntry), UserProfile + TrainingGoal + ProfileGoalsView, derived metrics layer (e1RM /
VolumeCalculator / ACWRCalculator / ProteinTarget / DataQualityValidator), ReflectionEngine
(nightly + post-session insights), Foundation Models LLM coach with RAGRetriever +
ExerciseHistoryTool + MuscleVolumeTool, ChatView with streaming + suggestion chips + thumbs
feedback, BackupService (local JSON export/import).

**V3 M1:** HRV SD-band model — 60-day baseline mean/SD, 7-day acute mean, ±0.75 SD bands,
HRVBandClassification, composite RecoveryScore (base 50 + HRV ±20 + RHR delta + sleep delta,
clamped 0–100), RecoveryEngine actor, HRVBandIndicator on Dashboard.

**V3 M2:** Retroactive HR-per-set — SetHeartRateData (SwiftData model), SetHRAttributionService
(actor, HKSampleQuery heartRate, ≥3 samples, set-window attribution, rest intervals),
SetHRAttributionMath, SetHRAttributionTrigger (45 s delay post-workout, re-attribution on HK
delta), SetHeartRateDataStore, SetHeartRateDisplay (color thresholds: ≥160 Warning, <120
Positive), WorkoutHistoryDetailView wired to show avgBPM per completed working set.

**Coach pipeline bugs (both fixed):** HevyCSVParser.buildSessions falls back to
`startTime + 3600` when all end_time cells are blank. CoachContextBuilder.buildRecentWorkouts
uses a 14-day startTime predicate (`$0.startTime >= twoWeeksAgo`) instead of the old
`endTime != nil` filter. 9 pipeline gap tests in `HevyImportPipelineGapTests.swift`.

---

## Key existing types you will use

```swift
// RecoveryScore (Signal/Signal/Signal/Data/Recovery/RecoveryScore.swift)
struct RecoveryScore: Sendable, Equatable {
    let value: Double                          // 0–100
    let hrvClassification: HRVBandClassification
    let confidence: RecoveryConfidence         // .low / .medium / .high
    let todayHRV: Double?                      // SDNN ms
    let todayRestingHR: Double?                // bpm
    // ... other fields
}

// HRVBandClassification (same file)
enum HRVBandClassification: String, Sendable {
    case aboveUpperBand, withinBand, belowLowerBand, insufficientData
}

// RecoveryEngine (Signal/Signal/Signal/Data/Recovery/RecoveryEngine.swift)
actor RecoveryEngine {
    static let shared: RecoveryEngine
    func computeScore(in context: ModelContext) async -> RecoveryScore
}
```

---

## V3 M3 Scope: watchOS Companion UI

### Goal

Display today's recovery score on the Apple Watch. The iPhone computes everything; the watch
is a read-only display surface. Communication is one-way (iPhone -> watch) via
`WCSession.updateApplicationContext` (battery-friendly, best-effort, no streaming).

---

### Part 1 — WatchPayload DTO

**File:** `Signal/Signal/Signal/Data/Watch/WatchPayload.swift`

```swift
struct WatchPayload: Codable, Sendable {
    let recoveryScore: Double           // 0–100, rounded to nearest integer for display
    let hrvClassification: String       // HRVBandClassification.rawValue
    let confidence: String              // RecoveryConfidence.rawValue
    let todayHRV: Double?               // SDNN ms, nil if unavailable
    let todayRestingHR: Double?         // bpm, nil if unavailable
    let lastUpdated: Date               // when the iPhone last pushed this

    // Convenience
    var scoreInt: Int { Int(recoveryScore.rounded()) }
    var scoreColor: String {            // semantic token name, decoded on watch
        if recoveryScore >= 70 { return "Positive" }
        if recoveryScore >= 40 { return "Warning" }
        return "Negative"
    }
}
```

`lastUpdated` serialises as ISO8601 seconds. Use `JSONEncoder` / `JSONDecoder` with
`.iso8601` date strategy throughout.

---

### Part 2 — iOS WatchConnectivityService

**File:** `Signal/Signal/Signal/Data/Watch/WatchConnectivityService.swift`

- A `@MainActor final class` (not actor — WCSession delegate must run on main thread)
  conforming to `WCSessionDelegate`.
- Singleton: `static let shared = WatchConnectivityService()`
- `activate()`: call `WCSession.default.delegate = self; WCSession.default.activate()` only
  if `WCSession.isSupported()`.
- `push(score: RecoveryScore)`: encode a `WatchPayload` from the score, call
  `WCSession.default.updateApplicationContext(dict)`. Catch and log errors. Only call when
  `WCSession.default.isPaired && WCSession.default.isWatchAppInstalled`.
- `WCSessionDelegate` stubs: implement `session(_:activationDidCompleteWith:error:)` and
  `sessionDidBecomeInactive` / `sessionDidDeactivate` (required on iOS). Log activation
  state changes under category `"watch"`.
- **Do not implement `session(_:didReceiveMessage:)` or `session(_:didReceiveApplicationContext:)`
  on iOS in this milestone** — data flows iPhone -> watch only.

Trigger: after `RecoveryEngine.shared.computeScore(in:)` returns (in DashboardViewModel or
wherever the dashboard already calls it), call `WatchConnectivityService.shared.push(score:)`.
Find where the dashboard currently calls the recovery engine and add the push there.

---

### Part 3 — watchOS receiver + UI

These files go in `Signal/Signal/SignalWatch Watch App/`. The human will add them to the
watch target in Xcode after you write them.

**File:** `Signal/Signal/SignalWatch Watch App/WatchConnectivityReceiver.swift`

- `@MainActor @Observable final class WatchConnectivityReceiver: NSObject, WCSessionDelegate`
- `var payload: WatchPayload? = nil`
- `func activate()`: `WCSession.default.delegate = self; WCSession.default.activate()` if
  supported.
- `func session(_:didReceiveApplicationContext:)`: decode `WatchPayload` from the dict,
  assign to `payload` on `MainActor`.
- Required stubs: `activationDidCompleteWith`, `sessionDidBecomeInactive`,
  `sessionDidDeactivate`.
- On first activation, check `WCSession.default.receivedApplicationContext` and decode any
  cached payload so the watch shows data immediately on launch, not only after the next push.

**File:** `Signal/Signal/SignalWatch Watch App/ContentView.swift` (replace existing placeholder)

Replace the current placeholder with a functional recovery display:

```
// Layout (watchOS-appropriate, no padding excess):
// Large number: today's score (e.g. "82") in .displayLarge equivalent
//   Color: green if >=70, orange if 40-69, red if <40
// Below: HRV classification label (e.g. "Above Baseline", "Within Range", "Below Baseline")
//   Map raw values: aboveUpperBand -> "Above Baseline", withinBand -> "Within Range",
//   belowLowerBand -> "Below Baseline", insufficientData -> "Tracking..."
// Below: "Updated X min ago" using lastUpdated (relative, e.g. "Updated 12 min ago")
// If payload is nil: show waveform.path.ecg icon + "Waiting for Signal" text
// No ScrollView needed — fits on 41 mm face
```

Wire `WatchConnectivityReceiver` as an `@State` or `@Environment` in `SignalWatchApp.swift`.
Call `receiver.activate()` in `.onAppear` or in the app's `init`.

**File:** `Signal/Signal/SignalWatch Watch App/SignalWatchApp.swift` (update, do not replace)

Add `@State private var receiver = WatchConnectivityReceiver()`, call `receiver.activate()`
on scene appear, and pass receiver into `ContentView` via `.environment` or direct init.

---

### Part 4 — Watch icon assets

watchOS requires a single `AppIcon` in the watch target's `Assets.xcassets`. The watch target
already has `Signal/Signal/SignalWatch Watch App/Assets.xcassets`. Update its `AppIcon.appiconset/Contents.json` to provide:

- A single `1024x1024` universal entry (`platform: "watchos"`, `idiom: "universal"`,
  `filename: "AppIcon1024.png"`).
- Do NOT try to generate the PNG — write only the `Contents.json`. The human will add the
  actual artwork. The JSON structure should match the watch single-size format accepted by
  Xcode 16+.

Sample `Contents.json`:
```json
{
  "images": [
    {
      "idiom": "universal",
      "platform": "watchos",
      "size": "1024x1024",
      "scale": "1x",
      "filename": "AppIcon1024.png"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

---

### Part 5 — Tests

**File:** `Signal/Signal/SignalTests/WatchPayloadTests.swift`

Write Swift Testing (`@Test`) tests:

1. `WatchPayload.scoreColor` returns `"Positive"` for 82, `"Warning"` for 55, `"Negative"` for 25.
2. `WatchPayload` round-trips through `JSONEncoder` / `JSONDecoder` (all fields equal, dates within 1 s).
3. `WatchPayload.scoreInt` rounds correctly: 82.4 -> 82, 82.6 -> 83.
4. `scoreColor` returns `"Positive"` for exactly 70, `"Warning"` for exactly 40.

These are pure-logic tests; no HealthKit or WCSession mocking needed.

---

## What you do NOT need to do in this milestone

- WCSession complication push / `transferCurrentComplicationUserInfo` — this milestone is
  application context only.
- WidgetKit / watchOS complications — deferred to V3 M3.5 or V4.
- Live workout HR streaming over WCSession — V4.
- CloudKit backup — already tracked for a later sub-milestone.
- Any changes to the coach, LLM, or RAG pipeline.

---

## Build targets to verify

1. **iOS target:** `xcodebuild -scheme Signal -destination 'platform=iOS Simulator,name=iPhone 17' build`
   Must build clean. The watch code on iOS side is in Signal/ (folder-synced), so it compiles automatically.

2. **Watch tests (logic only):** `xcodebuild -scheme Signal -destination 'platform=iOS Simulator,id=311A9753' test -only-testing:SignalTests/WatchPayloadTests`

3. **Watch target build:** `build_device` or watch scheme build after agent project edits. WCSession pairing does not work in the simulator.

---

## Acceptance criteria

- `WatchPayload` encodes/decodes cleanly; all 4 tests pass.
- iOS side compiles: `WatchConnectivityService` activates, push guard prevents calls when watch
  not paired, logger emits `"watch"` category entries.
- Watch side compiles: `WatchConnectivityReceiver` decodes `applicationContext` into a
  `WatchPayload` and publishes it; `ContentView` renders the score or the waiting state.
- `Assets.xcassets/AppIcon.appiconset/Contents.json` in watch target is updated to single-size
  universal format (no compiler warning about missing watch icon sizes).
- Output `READY TO COMMIT` when all acceptance criteria are met.

---

## Patterns to follow (from existing code)

```swift
// Actor + os.Logger pattern (copy from SetHRAttributionService.swift)
import os
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.cameronro.Signal",
    category: "watch"
)

// @Observable (copy from any ViewModel in Features/)
import Observation
@Observable final class SomeViewModel { ... }

// SwiftData ModelContext (copy from CoachContextBuilder.swift)
let context = ModelContext(modelContainer)
```

---

## Files to create / modify (summary)

| Action | Path |
|--------|------|
| CREATE | `Signal/Signal/Signal/Data/Watch/WatchPayload.swift` |
| CREATE | `Signal/Signal/Signal/Data/Watch/WatchConnectivityService.swift` |
| CREATE | `Signal/Signal/SignalWatch Watch App/WatchConnectivityReceiver.swift` |
| REPLACE | `Signal/Signal/SignalWatch Watch App/ContentView.swift` |
| UPDATE | `Signal/Signal/SignalWatch Watch App/SignalWatchApp.swift` |
| UPDATE | `Signal/Signal/SignalWatch Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json` |
| CREATE | `Signal/Signal/SignalTests/WatchPayloadTests.swift` |
| UPDATE | whichever file currently calls `RecoveryEngine.shared.computeScore(in:)` in the dashboard — add `WatchConnectivityService.shared.push(score:)` after the call |

Do not create any other files. Edit `project.pbxproj` only if folder sync does not pick up a required file and build fails.
