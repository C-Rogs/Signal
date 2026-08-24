# Signal efficiency and battery audit

Last updated: 2026-07-09

This document captures findings from a lifecycle and battery audit, what shipped as non-breaking fixes, and what remains for follow-up milestones.

## Principles

1. No background process should run without a defined stop condition.
2. Heavy work (Metal embeddings, Foundation Models, full reflection) must be gated on foreground stability.
3. Live workout hardware (phone `HKWorkoutSession`, watch streaming) must suspend when the user is not actively training in Signal.
4. HealthKit observer callbacks must always call `completionHandler` immediately; sync and inference defer to foreground policy.

## Shipped fixes (2026-07-09)

| Area | Change | Why |
|------|--------|-----|
| Phone HK workout | Suspend phone `HKWorkoutSession` on background even when workout is minimized to banner | Minimized + background left HR collection running |
| Deferred work policy | Minimized live session no longer blocks HK sync or Gemma release | Gemma (~300M) and sync stayed blocked for entire gym session |
| Embedding release | Release Gemma when overlay dismissed, regardless of minimized session | Same as above |
| Reflection | 60s debounce on `healthKitProcessDeltaDidFinish` path | Sync fan-out triggered parallel reflection + calendar FM |
| Dashboard | Removed `isSyncing` from `storeRefreshToken` | Calendar inference re-ran at sync start and finish |
| Coach | Cancel active send + release FM gate on tab disappear | FM generation continued after leaving Coach tab |
| Rest bell | Deactivate `AVAudioSession` after bell finishes | Session stayed active for entire workout |
| Metal waiters | Resume blocked `waitUntilMayUseMetal` waiters on background | Waiters held memory until next foreground |
| Root reflection | Guard foreground reflection with `resolvedIsInTrueBackground` | Safety net against background reflection |

## Verification scenario (highest priority)

1. Start live workout with phone HR source.
2. Minimize to banner.
3. Background app for 2+ minutes.
4. Confirm in Instruments: phone `HKWorkoutSession` ends, Gemma can release, HK sync can run on return.

## Remaining improvements (plan)

### P0: Live workout lifecycle policy

Define explicit states and document behavior:

| State | Phone HK | Watch HK | WCSession HR |
|-------|----------|----------|--------------|
| Viewing workout | On (if phone source) | On (if watch source) | On |
| Minimized banner, foreground | On | On | On |
| Background | **Off** (phone) | Policy TBD | Throttle or pause |
| Finished / discarded | Off | Off | Off |

Open question: when phone backgrounds with watch HR source, should watch keep streaming? Current behavior: yes (intentional for gym). Consider optional stop after N minutes background unless user opts in.

### P0: Unified system work coordinator

**Shipped 2026-07-09 (M1).** `SystemWorkCoordinator` actor sequences post-sync work:

```
sync complete → invalidate metrics → HR attribution → reflection (debounced) → watch push
```

### P1: HealthKit observer tiering

30 tier-1 types each have `HKObserverQuery` + hourly background delivery. Consider:

- Background delivery: sleep, HRV, workouts, active energy (high signal).
- Foreground-only: steps, nutrition detail, body mass (lower urgency).

Reduces passive hourly wakes.

### P1: Embedding foreground budget

Cap embed batches per foreground session (e.g. 4 days, then yield until next stable foreground). Prevents long Metal runs after large HK deltas.

### P1: Coach generation cancellation

`FoundationModelsCoach.respond` spawns an inner `Task` that is not tied to the caller's cancellation. Tab disappear releases the gate but FM may still run until completion.

Fix: structured concurrency with `withTaskCancellationHandler`, or hold generation `Task` handle and cancel on `abandonActiveWork`.

### P2: Vector search index

`SwiftDataVectorStore.nearestNeighbors` fetches all `HealthVector` rows (O(n) memory). Coach RAG will not scale. Partition by day or add persisted index.

### P2: Duplicate foreground sync entry points

`HealthKitBackgroundCoordinator` and `RootView` both trigger foreground sync. Both respect defer policy but can race. Consolidate behind `HealthKitManager.syncOnForegroundIfReady` idempotency.

### P2: Instrumentation

Extend `TrainWorkoutDiagnostics` with signposts:

- HK sync duration and embed batch count
- Active `HKWorkoutSession` state (phone + watch)
- WCSession send rate
- Reflection and FM inference start/end
- Gemma load/release events

Makes field battery reports actionable without guessing.

### P3: WCSession lifecycle

`WatchConnectivityService.activate()` at launch is standard for watch companion apps. Document expected radio cost. No change unless watch features are made optional.

## Good patterns already in place

- `AppLifecycleBroker` true-background generation counter
- `DeferredSystemWorkPolicy` foreground stability + train cooldown gates
- `HealthKitManager.cancelSyncForBackground`
- `EmbeddingRunPolicy.mayUseMetal` foreground gate
- Rest timer ticks only when `scenePhase == .active`
- `LiveWorkoutPhoneStopGate` dedupes in-flight phone stops
- HR telemetry throttle (1 Hz, batch cap 5)
- HK anchored queries stopped after callback
- `SetHRAttributionTrigger` cancels on background

## Review checklist for external audit

- [ ] Every `Timer` has a stop condition or scene-phase gate
- [ ] Every `HKObserverQuery` calls `completionHandler` synchronously
- [ ] No `while true` without bounded exit (Coach rate-limit retry is bounded)
- [ ] No network at runtime (privacy rule)
- [ ] `@Observable` not `ObservableObject`
- [ ] FM: no concurrent `LanguageModelSession` requests
- [ ] Background: Gemma released when idle, sync cancelled, phone HK suspended
- [ ] Tests cover lifecycle broker defer policy and phone stop gate
