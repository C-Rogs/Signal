# Builder handoff: HealthKit live workout teardown (blank after background)

**Date:** 2026-07-05  
**Priority:** Gate B blocker (Train live workout blank screen after home return)  
**Architect session:** profiling + Console capture proved mechanism; do not re-investigate unless fix fails verify.

---

## Problem

After **start workout → add set → finish → background → return**, the app shows a **blank screen**. User must force-quit and reopen.

Two failure modes exist in the field:

| Mode | Evidence | This handoff |
|------|----------|--------------|
| **A: Blank, same process** | Console capture `console-capture-20260705-210806.log` | **Primary target** |
| **B: New PID / cold relaunch** | Train diagnostics (`pid` change, `bgGen=0`) | Secondary; may improve if HK assertions released |

---

## Proven facts (do not relitigate)

1. **Not numpad-only.** Reproduces after `finishWorkout` with `workoutViewing=false`.
2. **Not RAM jetsam on capture run.** `footprintMB≈290`, `availableMB≈5800`; pid **7694** survived background.
3. **Console smoking gun at finish** (`21:08:20`):

   ```
   Signal(HealthKit)[7694] HKLiveWorkoutBuilder: Failed to update target construction state
   Error Domain=com.apple.healthkit Code=3
   Unable to transition from Error(7) state
   ```

4. **healthd** immediately acquires `HealthKit Background Workout (Reconnect)` on Signal.
5. **Keyboard had focus** at background (`21:08:33` KeyboardArbiter stealKeyboard).
6. Short no-workout background capture (`210535.log`) was **clean** (pid survived). Failure needs **workout finish** path.

---

## Root cause (code review + logs)

Phone live HR uses `LiveWorkoutPhoneSessionManager` (`HKWorkoutSession` + `HKLiveWorkoutBuilder`).

**Race on finish:**

```131:153:Signal/Signal/Data/Watch/LiveWorkoutWatchBridge.swift
    func endWatchWorkout() {
        ...
        case .phoneHealthKit:
            Task {
                await phoneSessionManager.stop(discardHealthKitWorkout: true)
            }
        ...
        resetStreamingState()  // sync: clears hasActivePhoneSession immediately
    }
```

- `stop()` is **fire-and-forget**; `resetStreamingState()` runs before HK teardown completes.
- `suspendForAppBackground()` only runs when workout **overlay** is up (`AppLifecycleBroker`). After finish, overlay is gone, so **no second chance** to stop HK on background.
- `LiveWorkoutPhoneSessionManager` delegate clears state on `.ended` while `stop()` may still be in flight:

```156:158:Signal/Signal/Data/Watch/LiveWorkoutPhoneSessionManager.swift
            if toState == .ended {
                clearWorkoutState()
            }
```

- `stop()` order: `stopActivity` → `endCollection` → `discardWorkout()` (correct for phone-as-sensor-only; watch/HK writer saves separately). If builder already `Error(7)`, transitions fail and healthd keeps reconnect assertion → bad suspend snapshot → **blank UI on return**.

---

## Implementation goals

1. **Deterministic HK teardown** before UI dismisses after finish/discard.
2. **No fire-and-forget** on phone HK stop.
3. **Idempotent stop** (safe if called twice: finish + background).
4. **Diagnostics** in `TrainWorkoutDiagnostics` for HK stop lifecycle.
5. **Dismiss keyboard** on finish/discard (keyboard was active at background in capture).

Do **not** implement MLX unload or workout UI rewrite in this milestone unless verify still fails after HK fix.

---

## Required changes

### 1. `LiveWorkoutWatchBridge`

- Change `endWatchWorkout()` → `func endWatchWorkout() async` (or `endWatchWorkout() async` + keep sync wrapper only if needed for call sites).
- For `.phoneHealthKit`: **`await phoneSessionManager.stop(...)`** then `resetStreamingState()`.
- For `.watch`: keep existing sync stop send; then `resetStreamingState()`.
- `suspendForAppBackground()`: if phone session still active (check `phoneSessionManager.isWorkoutActive` **or** internal flag), `await stop`. Do not rely only on `hasActivePhoneSession` if that was cleared early.
- Consider a private `isStoppingPhoneSession` guard to prevent concurrent `stop()` calls.

### 2. `LiveWorkoutPhoneSessionManager`

- Add `private var stopTask: Task<Void, Never>?` or `isStopping` gate; second `stop()` awaits first.
- Teardown order (verify against Apple HK live workout docs):
  1. `stopActivity(at:)`
  2. `await endCollection(at:)`
  3. `discardWorkout()` (keep discard: `HealthKitWorkoutWriter` owns saved workout)
  4. `session.end()`
- On **any** error: log + `TrainWorkoutDiagnostics.record("hkPhoneStop failed ...")`, still call `session.end()` and `clearWorkoutState()`.
- **Delegate:** do not `clearWorkoutState()` from `didChangeTo .ended` if `stop()` is driving teardown (use flag `isPerformingStop` or nil session only after stop completes). Prevents use-after-nil on builder.
- Log success: `hkPhoneStop ok discard=true`.

### 3. `ActiveWorkoutView`

- `finishWorkout()` / `discardWorkout()`:
  - `TrainKeyboard.dismiss()` before or after HK stop.
  - `await watchBridge.endWatchWorkout()` (function must be called from `Task` or make finish path async).
- Order suggestion: dismiss keyboard → **await HK stop** → `store.finishSession` → wellness → `resetTrainNavigation`.

### 4. Diagnostics

Add lines (examples):

- `hkPhoneStop begin discard=true`
- `hkPhoneStop end ok` / `hkPhoneStop end error=...`
- `endWatchWorkout awaited phoneStop`

`ProcessMemoryFootprint` + `recordMemory` already exist under `Features/Diagnostics/`.

### 5. Tests

Add `SignalTests/LiveWorkoutPhoneTeardownTests.swift` (or extend `LiveWorkoutTelemetryTests`):

- Bridge: after mocked/stubbed stop, `hasActivePhoneSession` false only when stop completes (if testable without HK hardware, test state machine with injectable manager protocol; minimal: test that `endWatchWorkout` is async and document HK integration as device gate).
- At minimum: unit test **idempotent stop gate** logic if extracted to pure function.

Do not block milestone on HK sim; **device verify is Gate A**.

---

## Out of scope

- MLX embedding park on background (Gate 2A, separate if pid-kill persists)
- Workout overlay remount / `backgroundReturnRemount`
- Watch app changes unless iPhone stop fix insufficient
- `project.pbxproj` unless new test file needs target membership (folder sync usually enough)

---

## Verify (Gate A agent)

Device: iPhone 16 Pro `00008140-001E34E10A01801C`

1. `build_device` → `install_app_device`
2. Repro:
   - Force-quit → open → wait tabs
   - Start workout → 1 set → **finish**
   - Home → 15s → return
3. **Pass:**
   - Tabs visible (not blank)
   - Profile → Train Workout Diagnostics: `hkPhoneStop end ok`, no mid-session `appLaunch` new pid
   - Same pid in diagnostics before/after background
4. **Fail:** paste diagnostics + say blank or new pid

Optional Console check: no `HKLiveWorkoutBuilder` `Error(7)` after finish.

---

## Key files

| Area | Path |
|------|------|
| Bridge | `Signal/Signal/Data/Watch/LiveWorkoutWatchBridge.swift` |
| Phone HK session | `Signal/Signal/Data/Watch/LiveWorkoutPhoneSessionManager.swift` |
| Finish UI | `Signal/Signal/Features/Train/ActiveWorkoutView.swift` |
| Background (overlay only) | `Signal/Signal/App/AppLifecycleBroker.swift` |
| Diagnostics | `Signal/Signal/Features/Train/TrainWorkoutDiagnostics.swift` |
| Capture evidence | `drafts/console-capture-20260705-210806.log` |

---

## Handover log

When milestone passes, append to `AGENT-BUILD-UPDATES.md` per `.cursor/rules/agent-build-handover.mdc`.

Declare: **MILESTONE COMPLETE: HK workout teardown, READY TO COMMIT** and wait for human commit.

---

## 2026-07-05 follow-up: Console repro `212450.log` (two more triggers)

Builder: **extend** this milestone (or immediate follow-up) with items below. HK await-stop shipped but blank persists.

### Trigger 1: Set value keypad (`SetValueEditorSheet`)

- Sheet auto-focuses keyboard (`isFieldFocused = true`); sets `isLiveWorkoutSetFieldEditing = true`.
- Console: `keyboardFocus` steal/detach at background (`21:26:49`, `21:26:52` on pid **7800**).
- **Fix:** On sheet `onDisappear` and on `scenePhase == .background`, call `TrainKeyboard.dismiss()`. Consider dismissing sheet automatically on background. Ensure `isLiveWorkoutSetFieldEditing = false` before suspend snapshot.

### Trigger 2: Wellness sheet swipe-down (session rating)

- `TrainWellnessFinishSheet` → `WellnessCaptureView` in `MainTabView` `.sheet(item:)`.
- **Swipe dismiss** hits binding `set { item == nil }` in `wellnessSheetItem`: only `recordFinishedSession` + `dismissWellness()`. Does **not** run `onSkip` / `completeFinishedWorkout` (no HK write, no wellness persist, no `workoutDidFinish` notification).
- Skip/Save paths are correct (`21:25:33` log: `saveWellness` on pid 7796).
- **Fix:** `.interactiveDismissDisabled(true)` on wellness sheet **or** route interactive dismiss through same path as Skip (`completeFinishedWorkout` with `saveWellness: false`). Add `TrainWorkoutDiagnostics.record("wellnessDismiss ...")` for swipe vs skip vs save.

### HK Error(7) still at workout **start** (separate)

Capture `21:25:03`: builder enters `Error(7)` immediately on `beginCollection`; healthd discards. Not fixed by await-stop on finish. Log auth state; do not start phone HK session if HealthKit read undetermined. See `HealthKitManager` / `LiveWorkoutPhoneSessionManager.start`.

### Process note

Multiple pids in session (7790→7791→7796→7800) include **user force-quit** (`0xDEADFA11` app switcher). Late repros on **7800** show background/foreground **without** pid change; blank can still be UI/keyboard/wellness state.

### Verify add-ons

1. Finish workout → **Save** on wellness → background → return (pass)
2. Finish → **swipe down** wellness sheet → background → return (must pass after fix)
3. Open set keypad → type digit → **Done** → background → return (must pass)
4. Open set keypad → type digit → background **without** Done (must not blank; dismiss keyboard)
