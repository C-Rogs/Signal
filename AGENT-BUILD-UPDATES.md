# Agent build updates

Log for the architect and review. Newest entries at the bottom.

---

## 2026-06-04 — V4 M1 Live workout HR (watch → iPhone)

### Shipped

- **iPhone:** `LiveWorkoutWatchBridge` starts watch via `HKHealthStore.startWatchApp(toHandle:)`, sends `sessionStart` / `sessionStop` over WCSession (`sendMessageData` when reachable, `transferUserInfo` when not). Ingests `heartRateBatch` into Train summary bar (HR column).
- **Watch:** `WatchLiveWorkoutSessionManager` runs `HKWorkoutSession` + `HKLiveWorkoutBuilder`, streams throttled HR to phone. Ends with `discardWorkout()` so iPhone `HealthKitWorkoutWriter` stays the single HK workout save.
- **Shared:** `LiveWorkoutTelemetryPacket` (Codable), `LiveWorkoutTelemetryThrottle`, tests in `LiveWorkoutTelemetryTests.swift`.
- **Session key:** `WorkoutSession.backupID` UUID string.

### Gate A (agent)

- XcodeBuildMCP `build_sim` succeeded.
- `LiveWorkoutTelemetryTests` (5) passed.
- Full `./scripts/build-and-test.sh` not re-run in agent shell (prior run hung on `| tail`).

### Gate B (human, paired devices)

1. `./scripts/install-watch-app.sh`
2. Run Signal on iPhone, Train → Start Workout
3. Watch shows **Train** + BPM (not just recovery score)
4. iPhone summary bar shows live HR
5. Finish on iPhone; no crash

Console: `category:watch`, `category:workout`.

### Human Xcode (watch target) — required for live workout

Add to **SignalWatch Watch App** if not compiling:

- `WatchAppDelegate.swift`
- `WatchLiveWorkoutSessionManager.swift`
- `WatchHealthKitAuthorization.swift`
- `LiveWorkoutTelemetry.swift` (mirror under watch folder must stay in sync with `Signal/Data/Watch/LiveWorkoutTelemetry.swift`)

**Capabilities (human, not agent):**

- HealthKit on watch app
- Background Modes: **Workout processing**
- Info.plist: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`

Also add `Signal/Data/Watch/LiveWorkoutTelemetry.swift` to watch target OR keep the mirrored copy in `SignalWatch Watch App/`.

### Field report (2026-06-04) — watch UI unchanged during workout

**Symptoms:** Complication works. Train workout started on iPhone; watch app still showed recovery / waiting, no workout UI. App icon on watch home screen has no logo.

**Root cause (agent):**

1. **No watch workout UI** — `ContentView` only rendered recovery `WatchPayload`; HK session could run with no visible change.
2. **sessionStart did not start HK** if `handle(_:)` from `startWatchApp` did not run first; only stored `sessionKey`.
3. **No watch HealthKit authorization** before `HKWorkoutSession` start.
4. **App icon:** A single `watchos` + `universal` 1024 slot was **invalid** (actool: "unassigned child", no `Assets.car` in the built `.app`). Fixed with a full watch **AppIcon** set (appLauncher, notificationCenter, quickLook, companionSettings, watch-marketing) via `scripts/generate-watch-app-icons.sh` from iOS `AppIcon.png`.

### Follow-up fix (same day)

- Watch **active workout UI** (Train label, BPM or spinner).
- `WatchHealthKitAuthorization` prompts once for workout + heart rate.
- `sessionStart` WCSession packet **starts** HK session when not already running (uses `activityTypeRawValue` from iPhone).
- `transferUserInfo` fallback for start/stop when phone app not reachable.
- Watch `didReceiveUserInfo` routes telemetry before recovery complication payload.

**Re-test after fix:** delete watch app → `./scripts/install-watch-app.sh` → grant Health on watch when prompted → start Train on iPhone.

### Watch home screen icon fix (2026-06-04)

- Root cause: `AppIcon.appiconset/Contents.json` used `platform: watchos` + `idiom: universal` only. Xcode actool treated the image as **unassigned** and shipped **no** `Assets.car`, so the home screen showed a blank placeholder.
- Fix: run `./scripts/generate-watch-app-icons.sh` to regenerate all required watch icon sizes + `Contents.json`.
- Verify after build: `SignalWatch Watch App.app/Assets.car` must exist inside the embedded watch bundle.

### Xcode Run does not install watch icons (2026-06-04)

- **Wrong:** Run **SignalWatch Watch App** scheme to the watch. That skips the iPhone embed path and often leaves an old or icon-less bundle on device.
- **Right:** Run **Signal** scheme to your **iPhone**, then `./scripts/install-watch-app.sh` (uninstalls old watch app, installs embedded bundle with `Assets.car`).
- Script now fails fast if `Assets.car` is missing and auto-detects `TARGET_BUILD_DIR` from your Xcode build settings.

### Out of scope (V4 M1)

- CueEngine live HR (V4 M2)
- Dynamic rest timer (V4 M2)
- Complication / Lock Screen widget data path (human parallel)
- Refactor `WatchConnectivityService` recovery push

### Files touched (V4 M1)

| Area | Files |
|------|--------|
| iOS | `LiveWorkoutTelemetry.swift`, `LiveWorkoutWatchBridge.swift`, `TrainWorkoutHealthKitConfiguration.swift`, `WatchConnectivityService.swift`, `WorkoutLiveSummary*.swift`, `ActiveWorkoutView.swift`, `TrainHomeView.swift`, `SignalApp.swift` |
| Watch | `WatchAppDelegate.swift`, `WatchLiveWorkoutSessionManager.swift`, `WatchHealthKitAuthorization.swift`, `LiveWorkoutTelemetry.swift`, `ContentView.swift`, `WatchConnectivityReceiver.swift`, `SignalWatchApp.swift` |
| Tests | `LiveWorkoutTelemetryTests.swift` |

---

## 2026-06-04 — Daily briefing accuracy (wrist temp + sleep timing)

### Problem (user report)

- Morning briefing claimed elevated sleeping wrist temperature after a night **without** the watch (stale or mis-attributed HealthKit sample).
- User asked whether Bedtime alarm / Sleep Focus ending could trigger the briefing. **No:** briefing is a local `UNCalendarNotificationTrigger` at Settings → Daily briefing time (default 7:00). Signal does **not** use Apple Sleep Score; recovery uses `sleepHours` from HealthKit sleep analysis.

### Root cause (agent)

1. **Frozen notification body** — `refreshSchedule` composed title/body once and scheduled `repeats: true`, so the same text fired every day until the app rescheduled.
2. **Stale morning data** — If the notification fired before HealthKit delta sync, content reflected the last reschedule (often prior evening), not post-wake metrics.
3. **Wrist temp false positive** — `ReadinessFlagEvaluator` flagged elevated wrist temp when `wristTemperatureDeltaC >= 0.5` with **no** requirement for overnight `sleepHours` on that wake day.

### Shipped

| Change | Detail |
|--------|--------|
| One-shot scheduling | `DailyBriefingScheduler.nextBriefingFireDate(from:briefingHour:briefingMinute:calendar:)`; `UNCalendarNotificationTrigger(..., repeats: false)` for the next fire only. |
| Reference day | Briefing content uses `startOfDay(for: fireDate)` so copy targets the wake day of the scheduled notification. |
| Shared compose | `DailyBriefingScheduler.composeBriefingContent(in:referenceDay:calendar:)` used by `refreshSchedule`. |
| Post-delivery reschedule | `DailyBriefingNotificationDelegate` (`UNUserNotificationCenterDelegate`) reschedules after present/tap; wired in `SignalApp` init. |
| Post-sync reschedule | `HealthKitManager` calls `refreshSchedule` after every successful `processDelta` (in addition to reflection path). |
| Wrist temp gate | `isWristTemperatureElevated` requires `sleepHours >= 1.0` on reference day before evaluating delta. |

### Tests (agent)

- `xcodebuild test` on simulator `id=20DDD35B-812A-49BE-9DCF-0685401ACC15`:
  - `SignalTests/DailyBriefingSchedulerTests` (3) — passed
  - `SignalTests/ReadinessFlagEvaluatorTests` (7, incl. `wristTemperatureFlagSuppressedWithoutSleep`) — passed

### Human Xcode (if not compiling)

Add to **Signal** iOS target if missing from project:

- `Signal/Core/Notifications/DailyBriefingNotificationDelegate.swift`
- `SignalTests/DailyBriefingSchedulerTests.swift`

(Agent did not edit `.pbxproj`; local test run succeeded, so targets may already include these files.)

### Gate B (human, device)

1. Night **without** watch: after morning unlock + HK sync, briefing body should **not** mention elevated sleeping wrist temperature when today has no `sleepHours`.
2. Set briefing to ~2 min ahead; lock phone overnight; after wake, open Signal or wait for background sync; pending notification body should match dashboard recovery for **today**.
3. Confirm briefing is **not** tied to Sleep Focus / alarm (only to Settings time + reschedule paths above).

### Files touched

| Area | Files |
|------|--------|
| Notifications | `DailyBriefingScheduler.swift`, `DailyBriefingNotificationDelegate.swift` (new) |
| App | `SignalApp.swift` |
| HealthKit | `HealthKitManager.swift` |
| Recovery | `ReadinessFlags.swift` |
| Tests | `DailyBriefingSchedulerTests.swift` (new), `ReadinessFlagEvaluatorTests.swift` |
