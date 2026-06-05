# Signal Performance Audit — June 2026

Privacy-first iOS 26+ Train tab battery and CPU pass. Findings from static audit; fixes applied where high impact was confirmed.

## A. Train active workout

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| 1 Hz `tick` invalidated full `ForEach` + all set rows | P0 | `ActiveWorkoutView` `Timer.publish` + `_ = tick` in `liveSummary` / `activeRestTimer` | **Fixed:** timer moved to `ActiveWorkoutRestTimerLayer` + `WorkoutLiveSummaryBar` `TimelineView` |
| `lastHint(for:)` SwiftData fetch per exercise per tick | P0 | `LastSessionAutofill.findLastExercise` in view body | **Fixed:** `ExerciseSessionHintCache` warms once per exercise |
| `previousHint(for:)` fetch per set per tick | P0 | `WorkoutExerciseSectionView.setRow` body | **Fixed:** cached templates via `hintCache` |
| `reloadSessionRecoveryScore` on every set commit | P1 | `onNeedsRefresh` called `RecoveryEngine.todayReadinessBundle` | **Fixed:** only on appear + foreground |
| `WorkoutLiveSummary.compute` every second | P1 | `_ = tick` forced full volume scan | **Fixed:** `volumeStats` on data change; duration in `TimelineView` |
| `applyDynamicRestExtension` every tick | P2 | Runs in rest layer timer only | **Acceptable:** early-outs when no rest; 20s throttle unchanged |
| `SetRowView` save on focus loss | P2 | `commitSetFields` → `context.save()` | **Acceptable:** no per-keystroke saves |
| `scenePhase` background save | P2 | Single `modelContext.save()` | **Acceptable** |
| P0 keyboard/banner paths | — | `TrainScenePhaseKeyboardPolicy`, `tabViewBottomAccessory` | **Untouched** |

## B. Live HR + Watch bridge

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| Dual phone + watch HK sessions | P2 | `LiveHeartRateSourcePolicy` exclusive branch | **Acceptable:** one source locked per session |
| WC `sendMessageData` at 1 Hz when reachable | P2 | `WatchLiveWorkoutSessionManager.flushPendingHeartRate` | **Deferred:** needs device A/B; documented tradeoff |
| HR UI coupled to parent tick | P1 | `heartRateUIState(now: tick)` in parent body | **Fixed:** HR staleness in summary `TimelineView` |
| `retryPendingOutboundTelemetry` on foreground | P2 | `RootView` scenePhase | **Fixed:** 2s debounce in bridge |

## C. HealthKit sync + background delivery

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| Observer `completionHandler` | P2 | `HealthKitBackgroundCoordinator` calls immediately | **Acceptable** |
| Parallel sync on foreground | P1 | `isSyncing` set after `await refreshAccessStateAsync` | **Fixed:** claim `isSyncing` before `Task` spawn |
| Duplicate foreground triggers | P2 | `RootView` + `willEnterForeground` both call deferred sync | **Mitigated:** `isSyncing` guard; second call no-ops |
| `.hourly` background delivery | P2 | ~30 Tier 1 observers | **Acceptable:** intentional dirty-flag coalescing |

## D. MLX / embeddings / Coach

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| Metal in background | P2 | `EmbeddingRunPolicy.mayUseMetal` | **Acceptable** |
| Model resident after preload | P2 | `GemmaEmbeddingService.ensureLoaded` | **Acceptable:** document footprint |
| Foreground reflection spam | P2 | `ReflectionSchedule.shouldRunOnForeground` | **Acceptable** |
| FM parallel requests | P2 | `isResponding` + `FoundationModelsInferenceGate` | **Acceptable** |

## E. Dashboard + SwiftUI data flow

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| Full reload on tab/foreground | P2 | `DashboardView.reloadViewModel` | **Acceptable:** not on 1 Hz path |
| Window toggle refetches HK | P2 | `recomputeSeriesForSelectedWindow` only | **Acceptable** |
| `TrainHomeView` unbounded `completedSessions` | P2 | UI uses `prefix(10)` | **Deferred:** not workout hot path |

## F. Logging + I/O

| Finding | Severity | Evidence | Resolution |
|---------|----------|----------|------------|
| Per-sample HR `.info` | P1 | `LiveWorkoutWatchBridge`, phone session, watch flush | **Fixed:** demoted to `.debug` |
| Dynamic rest extend `.info` | P1 | `ActiveWorkoutRestTimerCoordinator` | **Fixed:** `.debug` |
| Per-set cue `.info` | P1 | `WorkoutExerciseSectionView` | **Fixed:** `.debug` |
| `Log.ui.info` on scenePhase | P2 | Transition only | **Acceptable** |

## Gate B device template (human)

| Field | Value |
|-------|-------|
| Device | iPhone 16 Pro |
| iOS | 26.x |
| Watch paired | Y/N |
| Scripted session | 15–90 min Train, 2–3 rests, switcher 5×, lock during rest |
| Energy impact | Settings → Battery → Signal (note before/after) |
| HK duplicate session | Confirm phone HK inactive when watch source live |
| P0 regression | No blank workout after switcher; keyboard resumes |

## Tradeoffs retained

- Watch HR uses interactive WC when reachable (~1 msg/s): best live UX; watch battery cost.
- Gemma model stays loaded after preload: faster Coach/import; ~hundreds MB RAM.
- HK observers on all Tier 1 types: reliable dirty wakes; OS coalesces delivery.
