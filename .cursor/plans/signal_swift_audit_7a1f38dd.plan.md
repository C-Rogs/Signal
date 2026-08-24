---
name: Signal Swift Audit
overview: Consolidate workout lifecycle into AppLifecycleBroker; remove snapshot privacy shield entirely (user accepts live workout in app switcher). Nav-push kept per Log13. View stays mounted on home return; watchdog remount only on corruption. Agent owns build+sim tests; human Gate B watches for kills.
todos:
  - id: a-workout
    content: "A Workout reliability: AppLifecycleBroker + DELETE hideBodyForSnapshot/shield + nav/tab hardening + exercise-detail nav + hoist watch-start flag + dead file delete + unit tests"
    status: pending
  - id: b-perms
    content: "B Permissions & gates: SetHRAttribution HK gate, HK denied probe, Dashboard auth await, embedding preload when minimized, ImportView foreground reset, optional wellness/HK ordering"
    status: pending
  - id: c-perf
    content: "C Perf & bootstrap: Dashboard debounce + 60d bounded queries, catalog ModelActor seed, StableID save fix, SignalApp bootstrap 30s timeout"
    status: pending
  - id: d-agent-verify
    content: "D Agent verify: test_sim all lifecycle tests, build_device install launch, parse TrainWorkoutDiagnostics expectations, append AGENT-BUILD-UPDATES.md"
    status: pending
  - id: e-human-gate-b
    content: "E Human Gate B only: home×3 numpad scroll stable, NC×5 no kill, lock 10s; watch for watchdog relaunch (appLaunch mid-session)"
    status: pending
isProject: false
---

# Signal Swift App: Implementation Plan

**Goal:** Reliable home / NC / app-switcher return. No blank workout body. Permissions honest. Agent does all verifiable gates; you only spot-check gym feel and kill repro.

---

## Why the privacy shield existed (and why we are removing it)

The shield (`hideBodyForSnapshot` / solid-color body on background) was **not** about hiding your data from you. It was added in Log9-Log13 to:

1. Reduce iOS **watchdog kills** when the system snapshots a heavy `ScrollView` + `TextFields` + keyboard for the app switcher
2. Avoid a live workout preview in the switcher (cosmetic)

**Your call:** stale switcher preview is fine. The shield also introduced the main **blank-screen failure mode** (body hidden on background, restore handlers race and miss). **Remove it entirely.**

**Tradeoff we accept:** home + numpad may reintroduce rare `0x8BADF00D` kills (Log9). Gate E watches for `appLaunch` mid-session. **Primary path matches Apple-native advice:** leave UI mounted, clear focus only. If kills return, use contingency ladder below (not body hide).

---

## Alignment with external lifecycle advice

| Advice | Plan position |
|--------|---------------|
| Drop shield; leave view mounted; clear focus only | **Track A primary path** (correct, leanest) |
| Shield causes layout recalc during OS snapshot → kills | **Why we remove it**; was likely #1 kill/blank contributor |
| Alt 4: push lightweight summary on background | **Rejected** (same class of hierarchy swap as shield; foreground sync headaches) |
| Alt 3: UIKit list interop | **Out of scope**; last resort only if A + contingencies fail |
| Alt 1: `beginBackgroundTask` on `didEnterBackground` | **Contingency A1** if Gate E shows kills after shield removal |
| Alt 2: offload saves off MainActor | **Contingency A2**; partial overlap with Track C `ModelActor` pattern |

### If Gate E still shows kills: main-thread suspect order (from code)

1. **`hideBodyForSnapshot` layout swap** (removed in A): tears down `ScrollView` + `TextField`s exactly when iOS snapshots. Matches advice about violently ripping out hierarchies.
2. **Synchronous SwiftData on focus loss**: `SetRowView` → `store.commitSetFields` → `onNeedsRefresh()` on main actor. Background path uses `prepareForSystemOverlay` + `suppressNextCommit` to skip commit; broker must guarantee **one** dismiss path so suppress never races. Audit in A2.
3. **`LiveWorkoutWatchBridge.suspendForAppBackground()`**: `await phoneSessionManager.stop(...)` HealthKit workout teardown. Runs from `Task` on main actor today. Contingency A1 wraps this + any final save.
4. **Foreground-only weight** (not background kill, but worth noting): `reloadSessionRecoveryScore()` / `RecoveryEngine.todayReadinessBundle` in deferred recovery runs on **return**, not during snapshot.

**Most likely historical killer:** #1 (shield). **Most likely if kills persist after A:** #2 commit leak, then #3 HK stop duration.

### Contingency ladder (only if Gate E fails)

**A1: `beginBackgroundTask` (OS-sanctioned breathing room):**
- On broker `didEnterBackground` when workout presented: `beginBackgroundTask(withName: "WorkoutSuspend")`
- Inside task: keyboard dismiss, focus clear (no commit), `await suspendForAppBackground()`, optional `modelContext.save()` if dirty
- `endBackgroundTask` in `defer`; log elapsed ms in diagnostics
- No UI changes

**A2: Defer commit/save off hot path:**
- If diagnostics show `setRow commit` on background despite suppress: harden suppress (single broker-owned dismiss, remove duplicate NC handlers in `ActiveWorkoutView`)
- If commits are legitimately needed: queue `commitSetFields` to background `ModelContext` / actor; UI updates on foreground
- Reuse `ModelActor` pattern from Track C

**A3: UIKit list (nuclear):** not planned unless A + A1 + A2 fail Gate E twice.

---

## Deterministic foreground model

Compared to Hevy / Strong (workout view stays mounted, no body swap):

| Pattern | Signal today | Signal after A |
|---------|--------------|----------------|
| Workout presentation | Nav push (Log13) | Same |
| App switcher | Solid color shield hides workout | **Live workout visible** (user OK) |
| Return from home | Shield lift + `listRecoveryToken` + remount races | **View never hidden**; scroll preserved |
| Corruption recovery | Competing paths | Watchdog only: `blankBodyDetected` remount |

### Exact behavior after Track A

**True background (`UIApplication.didEnterBackground`):**
1. Broker sets `isInTrueBackground = true`
2. **Workout list stays rendered** (no shield, no `hideBodyForSnapshot`)
3. `TrainKeyboard.dismiss()` + `SetRowView` focus clear (`prepareForSystemOverlay`, no commit)
4. `LiveWorkoutWatchBridge.suspendForAppBackground()`
5. Diagnostics only: `noteWorkoutViewDisappearedWhilePresented`

**Return to foreground:**
1. Broker sets `isInTrueBackground = false`
2. **Nothing to restore visually** (view was always visible)
3. `scheduleDeferredHomeRecovery` (500ms): hints, volume, `reloadSessionRecoveryScore`, `ensureWatchWorkoutStarted` (coordinator flag)
4. **No `workoutSurfaceGeneration` bump** on happy path

**Watchdog (500ms after foreground, only if corrupted):**
- If `orderedExercises.isEmpty` && `session.exercises.count > 0` → `requestWorkoutSurfaceRefresh("blankBodyDetected")`

**Inactive only (NC, app switcher preview):**
- **No** body hide
- **No** generation bump
- **No** keyboard dismiss (Log9)

---

## Other revamps bundled in A/B/C

| Revamp | Track |
|--------|-------|
| Hoist `didInitialWatchStart` → `LiveWorkoutCoordinator` | A |
| `SignalApp` bootstrap 30s timeout | C |
| `ImportView` foreground reset | B |
| Exercise detail history nav in sheet | A |
| Delete 5 dead overlay/shield files + `project.pbxproj` | A |
| Optional: prune dead route tokens post-Gate B | A tail |

**Out of scope:** Coach FM, Watch lifecycle, Live Activity, `TrainHomeView.completedSessions` query limit.

---

## BLOCKER: no RootView overlay

Log10-Log13: overlay caused kills; nav-push is stable. Delete `ActiveWorkoutShell.swift`; keep `TrainHomeView` push lines 367-370.

---

## Track A: Workout reliability (agent-owned)

### A1. AppLifecycleBroker
- New `AppLifecycleBroker.swift` (`@MainActor @Observable`)
- Move NC registration from `TrainKeyboard.swift` lines 34-114
- Inject in `SignalApp.swift`; migrate HK gating flags
- Replace per-view NC observers in `ActiveWorkoutView`, `SetRowView`, `TrainHomeView`

### A2. Remove snapshot shield + single background dismiss path
- **Delete** `hideBodyForSnapshot`, `listRecoveryToken`, all shield restore handlers from `ActiveWorkoutView`
- **Do not** add any body-hide modifier on background
- **Single broker-owned** `didEnterBackground` handler: dismiss keyboard → broadcast focus dismiss with `suppressNextCommit` → `Task { await suspendForAppBackground() }` (optionally inside A1 background task if needed)
- Remove duplicate `didEnterBackground` / `willEnterForeground` NC handlers from `ActiveWorkoutView` (today duplicates `TrainApplicationLifecycle` + causes double dismiss)
- **Do not** bump `workoutSurfaceGeneration` on normal background→active
- Watchdog in `scheduleDeferredHomeRecovery` only

### A3. Nav + tab hardening
- `TrainHomeView` 92-98: guard before `path.removeAll()` on empty `liveSessions`
- Path-pop grace 2.5s or `isForegroundRecoveryInFlight`
- `ActiveWorkoutContainerView`: 3s resolve timeout
- `MainTabView`: always `tabViewBottomAccessory` branch
- Exercise detail sheet: `navigationDestination(for: TrainRoute.self)` for history

### A4. Coordinator session flags
- `didStartWatchForSessionID` on coordinator replaces view `@State didInitialWatchStart`

### A5. Dead code + project
- Delete: `ActiveWorkoutShell`, `TrainWorkoutPrivacyShield`, `TrainWorkoutSnapshotShell`, `TrainSecureSnapshotField`, `StaleActiveWorkoutRouteView`
- Edit `project.pbxproj`

### A6. Tests
- Keep `testInactiveReturnDoesNotRemountWorkoutSurface`
- Keep `testBackgroundReturnDoesNotRemountWithoutDisappearFlag`
- Add `testBlankBodyDetectedRequestsRemount`
- Migrate `TrainApplicationLifecycleTests` → broker

---

## Track B: Permissions & gates (agent-owned)

| Fix | File |
|-----|------|
| SetHRAttribution: no HK prompt unless `.ready` | `SetHRAttributionService.swift` |
| Probe after prompt; `.denied` on deny-all | `HealthKitAuthorization.swift`, `HealthKitManager.swift` |
| `await refreshAccessStateAsync()` before pull-to-refresh | `DashboardView.swift` |
| Embedding preload when minimized | `RootView.swift` |
| Import stuck flags on foreground | `ImportView.swift` |

---

## Track C: Perf & bootstrap (agent-owned)

| Fix | File |
|-----|------|
| Debounce `reloadViewModel`; decouple Watch push | `DashboardView.swift`, `DashboardViewModel.swift` |
| Bound queries ≥60 days | `DashboardView.swift` |
| Catalog seed via `ModelActor` | `ExerciseCatalogSeeder.swift`, `CatalogBootstrap.swift` |
| StableID without context `save()` | `WorkoutSession+StableID.swift` |
| Bootstrap 30s timeout | `SignalApp.swift` |

---

## Track D: Agent verification

1. `test_sim` lifecycle + coordinator tests
2. `build_device` → `install_app` → `launch_app`
3. Append `AGENT-BUILD-UPDATES.md`

---

## Track E: Human Gate B (you only)

After D. **15 min gym session**, then:

| # | You do | Pass |
|---|--------|------|
| 1 | Home ×3 with numpad open | List visible; scroll stable |
| 2 | NC ×5 with numpad | No kill (`appLaunch` absent mid-session); body visible |
| 3 | Lock 10s, unlock | Body + keyboard OK |

Copy Train diagnostics if any fail. **Kill watch:** if app relaunches mid-workout, shield removal may need keyboard-only mitigation (not body hide).

---

## What NOT to do

| Rejected | Why |
|----------|-----|
| RootView overlay | Log10-Log13 |
| `hideBodyForSnapshot` / privacy shield / summary route on background | User decision + advice: hierarchy swap during snapshot |
| Unconditional remount on home return | Destroys scroll |
| Remount on inactive→active | Log9 + tests |
| Keyboard dismiss on `willResignActive` | Log9 |
| `listRecoveryToken` | Competing recovery |
| Tab tree swap for banner | iOS 26.1 watchdog |

---

## Execution order

```
A → D (agent) → E (you) → B + C parallel → D again
```

**To execute:** say "implement A" or "go ahead".

---

## Architect delegation pack

Use this section to brief builder agents. Full design context stays in this plan; builders get one track at a time. Log outcomes in [`AGENT-BUILD-UPDATES.md`](AGENT-BUILD-UPDATES.md) per [`.cursor/rules/agent-build-handover.mdc`](.cursor/rules/agent-build-handover.mdc).

### Architect reads first

| Doc | Why |
|-----|-----|
| This plan | Source of truth for behavior and rejections |
| [`AGENT-BUILD-UPDATES.md`](AGENT-BUILD-UPDATES.md) (latest `##` down) | What already shipped |
| [`.cursorrules`](.cursorrules) | Device-first MCP, no em dashes, Swift 6 patterns |
| [`.cursor/rules/xcode-project-setup.mdc`](.cursor/rules/xcode-project-setup.mdc) | `project.pbxproj` edits + verify |
| [`AGENT-BUILD-UPDATES.md`](AGENT-BUILD-UPDATES.md) Log10-Log13 | Why overlay/shield are banned |

### Repo constraints (every builder)

- iOS app only; privacy-first; no new dependencies without approval
- Verify: `build_device` → `install_app` → `launch_app` on iPhone 16 Pro `id=00008140-001E34E10A01801C`
- Unit tests: `test_sim` pinned sim `id=20DDD35B-812A-49BE-9DCF-0685401ACC15`
- After `project.pbxproj` / deletions: log under **Xcode project** in handover
- **Do not** implement contingencies A1/A2/A3 unless architect explicitly assigns after human Gate E failure

### Delegation matrix

| Order | Track | Agent | Blocks | Parallel OK? |
|-------|-------|-------|--------|--------------|
| 1 | **A** | Builder 1 | everything | No |
| 2 | **D** | Same or verify agent | E | No |
| 3 | **E** | Human (Cameron) | B, C, contingencies | No |
| 4 | **B** + **C** | Builder 2 + 3 (or one agent, two commits) | final D | B ‖ C only after E pass |
| 5 | **D** | Verify agent | done | No |
| 6 | **A1/A2** | Only if E fails kills | n/a | Architect decision |

---

### Builder brief: Track A (copy to agent)

**Mission:** Workout lifecycle consolidation. Remove shield. One broker. Nav-push unchanged.

**In scope:**
- `Signal/Signal/App/AppLifecycleBroker.swift` (new)
- `TrainKeyboard.swift`, `SignalApp.swift`, `RootView.swift`
- `ActiveWorkoutView.swift`, `ActiveWorkoutContainerView.swift`, `SetRowView.swift`
- `TrainHomeView.swift`, `MainTabView.swift`, `LiveWorkoutCoordinator.swift`
- `ActiveWorkoutView.swift` sheet: `navigationDestination` for `TrainRoute.history`
- Delete 5 dead files; edit `project.pbxproj`
- Tests: `LiveWorkoutCoordinatorScenePhaseTests.swift`, `TrainApplicationLifecycleTests.swift` (rename/migrate)

**Acceptance criteria (Gate A):**
- [ ] No `hideBodyForSnapshot`, `listRecoveryToken`, or privacy shield code remains
- [ ] Single `didEnterBackground` path via broker (no duplicate handlers in `ActiveWorkoutView`)
- [ ] Background: keyboard dismiss + focus clear with `suppressNextCommit` (no SwiftData commit on diagnostics)
- [ ] Foreground: view stays mounted; no `workoutSurfaceGeneration` bump unless watchdog fires
- [ ] `test_sim` passes including new `testBlankBodyDetectedRequestsRemount`
- [ ] `build_device` + install + launch passes

**Out of scope for this agent:** Track B/C, `beginBackgroundTask` (A1), UIKit list (A3), RootView overlay, route-token prune (optional tail)

**Handover title:** `## YYYY-MM-DD - Swift lifecycle Track A`

---

### Builder brief: Track B (copy to agent)

**Mission:** Permission and gate honesty. No launch-time HK sheet. Embedding when minimized.

**Prerequisite:** Track A + human Gate E passed (or architect waives).

**In scope:** `SetHRAttributionService.swift`, `HealthKitAuthorization.swift`, `HealthKitManager.swift`, `DashboardView.swift`, `RootView.swift`, `ImportView.swift`; optional `SettingsView.swift`

**Acceptance criteria:**
- [ ] Cold launch does not show HealthKit sheet without user tap
- [ ] Deny-all Health shows `.denied` and Dashboard banner/Open Settings
- [ ] Pull-to-refresh awaits `refreshAccessStateAsync()` before sync check
- [ ] Minimized live session (`activeSession` && !`isViewingActiveWorkout`) allows embedding preload
- [ ] `build_device` passes

**Handover title:** `## YYYY-MM-DD - Swift lifecycle Track B`

---

### Builder brief: Track C (copy to agent)

**Mission:** Perf and bootstrap. No workout lifecycle changes.

**Prerequisite:** Track A + human Gate E passed (or architect waives). Safe to parallel with B.

**In scope:** `DashboardView.swift`, `DashboardViewModel.swift`, `ExerciseCatalogSeeder.swift`, `CatalogBootstrap.swift`, `WorkoutSession+StableID.swift`, `SignalApp.swift`

**Acceptance criteria:**
- [ ] Dashboard `reloadViewModel` debounced; Watch push decoupled from reload
- [ ] Metrics/nutrition queries bounded ≥60 days (rolling means correct)
- [ ] Catalog seed off main actor (`ModelActor`); launch shell not blocked after first frame
- [ ] `resolvedSessionID` does not call context-wide `save()`
- [ ] Bootstrap shows `AppLaunchFailureView` after 30s SwiftData hang
- [ ] `test_sim` + `build_device` pass

**Handover title:** `## YYYY-MM-DD - Swift lifecycle Track C`

---

### Verify agent brief: Track D

**After A:** `test_sim` lifecycle tests; `build_device` install launch; handover with Gate A filled, Gate B = "awaiting human Gate E"

**After B+C:** full `test_sim`; `build_device`; handover with all gates

**Diagnostic strings to expect after A (from TrainWorkoutDiagnostics):**
- No `hideBody=` / `restoreBody` / `listRecoveryToken` lines (removed)
- Background: `appDidEnterBackground`, `livePhoneSession suspendedForBackground`
- Foreground: `homeForegroundReturn completed`; no `appLaunch` mid-session during agent testing
- No `refreshWorkoutSurface` on normal home return (only `blankBodyDetected` if forced)

---

### Human brief: Track E (Cameron)

15 min workout, numpad used. Three checks only (see table above). If `appLaunch` appears mid-session → tell architect to assign **Contingency A1**, not shield.

---

### Gaps architects must still judge (not in code)

| Situation | Architect action |
|-----------|------------------|
| Gate E kill repro | Assign A1 builder brief (from contingency section) |
| Gate E blank but no kill | Check diagnostics for `blankBodyDetected`; may need nav guard tweak in A follow-up |
| `B` and `C` touch same file (`DashboardView`, `RootView`) | One agent or strict merge order: B first, then C |
| Route-token prune (A tail) | Only after E pass + diagnostics show tokens unused |

### Is the plan complete for architect handoff?

**Yes for sequencing, behavior, rejections, and per-track builder briefs above.**

**Architect still supplies at dispatch:** branch name, whether to waive Gate E before B/C, and contingency assignment if E fails. Builders should not read the whole audit thread; this plan + their track brief is enough.
