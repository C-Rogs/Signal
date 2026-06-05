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

### Watch app crash on launch + complication "—" (2026-06-04)

**Symptoms:** After install, complication shows **—** (waiting). Opening the watch app closes immediately, even during an iPhone Train workout.

**Root cause:**

1. **Launch crash:** `ContentView` called `prepareOnLaunch()` → `requestAuthorization` without `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` on the watch target (fatal). Watch entitlements also lacked `com.apple.developer.healthkit`.
2. **Complication dash:** `RecoveryWidgetSnapshot.waiting` when no payload in App Group / WCSession context (expected until iPhone pushes recovery).

**Code fix (agent):**

- Removed launch-time HealthKit authorization.
- `WatchHealthKitAuthorization.isConfiguredForHealthKit` gates all HK calls.
- `WatchConnectivityReceiver` hydrates from WCSession context **and** `WatchPayloadCache` app group.
- Added `SignalWatch Watch App/WatchApp-Info.plist` (health strings + `workout-processing`).
- Added HealthKit entitlement to `SignalWatch Watch App.entitlements`.

**Human Xcode (required once):**

1. **SignalWatch Watch App** target → **Build Settings** → set **Info.plist File** to `SignalWatch Watch App/WatchApp-Info.plist` (or paste the three keys from that file into the target **Info** tab).
2. **Signing & Capabilities** → add **HealthKit** and **Background Modes** → **Workout processing** (must match entitlements + provisioning).
3. Clean build **Signal** to iPhone → `./scripts/install-watch-app.sh` → open watch app → grant Health when prompted.

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

---

## 2026-06-04 — V4 M2 Live HR cues + dynamic rest (simulator-safe)

### Shipped

- **Policy module:** `LiveWorkoutAutoregulation.swift` with elevated HR threshold (150 BPM), fresh sample window (45 s), rest extension (+30 s, max 2 per rest, 20 s throttle, skip when ≤8 s left).
- **Set-complete HR cue:** After a working set, `LiveHRCueEvaluator` appends `Heart rate still {bpm}. Take the full rest.` when watch HR is fresh and ≥150; composes with existing tier cue on a second line.
- **Dynamic rest:** `ActiveWorkoutView` evaluates HR each second during an active rest; extends timer and shows `+30s, HR still {bpm}` on `FloatingRestTimerBar` (accessibility id `dynamicRestNotice`).
- **Handoff:** `HANDOFF-V4M2.md` for builder/architect continuity.

### Gate A (agent)

- XcodeBuildMCP `test_sim` (simulator profile): `SignalTests/LiveWorkoutAutoregulationTests` (9) + `SignalTests/CueEngineTests` (26) passed (35 total in run).
- iOS folder sync compiles new Swift without pbxproj edits.

### Gate B (human, paired iPhone + Watch)

Run at home. Each test names the **revisit** milestone if it fails.

| ID | Test | Pass criteria | If fail, revisit |
|----|------|---------------|------------------|
| **D1** | Watch install | `./scripts/install-watch-app.sh` succeeds; embedded bundle contains `Assets.car`; watch home icon visible | V4 M1 watch packaging |
| **D2** | Live HR stream | Start Train on iPhone; within 30 s summary bar shows BPM; Console `category:workout` logs `live HR bpm=` | **V4 M1** telemetry |
| **D3** | Watch workout UI | Watch shows **Train** + BPM during session (not recovery-only screen) | **V4 M1** watch UI / WCSession start |
| **D4** | HR set cue | Complete a hard working set while BPM ≥150 on summary bar; set banner includes `Heart rate still` line | **V4 M2** cues (this milestone) |
| **D5** | HR cue without watch | Complete a set with no watch paired; only tier cue (no `Heart rate still` line) | **V4 M2** (expected pass offline) |
| **D6** | Dynamic rest extend | Auto-rest after set; keep moving; timer adds ~30 s twice max; amber `+30s, HR still` notice | **V4 M2** dynamic rest |
| **D7** | Dynamic rest idle HR | Sit still until BPM below 150 before rest ends; no further auto-extensions | **V4 M2** policy |
| **D8** | Finish workout | Finish on iPhone; no crash; single HK workout on phone; watch session ends | **V4 M1** save path |

**Briefing (uncommitted local):** if wrist-temp copy wrong after night without watch, run briefing Gate B from the 2026-06-04 daily briefing section (not V4).

### Human Xcode

- None for iOS (folder sync). Watch target unchanged from V4 M1.

### Out of scope

- Load/RPE autoregulation (prescription changes)
- Google Calendar (later V4)
- Simulator injection of fake HR (no watch in office)

### Files touched

| Area | Files |
|------|--------|
| Workout logic | `LiveWorkoutAutoregulation.swift` (new) |
| Train UI | `ActiveWorkoutView.swift`, `WorkoutExerciseSectionView.swift`, `FloatingRestTimerBar.swift`, `SetCueBannerView.swift` |
| Tests | `LiveWorkoutAutoregulationTests.swift` (new) |
| Handoff | `HANDOFF-V4M2.md` (new) |

---

## 2026-06-04 — V4 M3 In-session load autoregulation (readiness + RPE)

### Shipped

- **Load policy:** `LiveLoadAutoregulation.swift` with recovery bands (≥70 / 40 to 69 / <40), RPE tiers aligned with CueEngine, and suggest-only load lines (hold, +2.5 kg, grind stay).
- **Composed banner:** `LiveSetCueComposer` stacks tier → HR → load (max 3 lines) in `LiveWorkoutAutoregulation.swift`.
- **Train UI:** `WorkoutExerciseSectionView` emits load nudge after set complete; `ActiveWorkoutView` + `WorkoutLiveSummaryBar` show **Low recovery day** chip when score < 40.
- **Recovery snapshot:** `RecoveryEngine.todayRecoveryScore(in:)` for synchronous workout session use.
- **Handoff:** `HANDOFF-V4M3.md` with Gate B D9–D12.

### Gate A (agent)

- XcodeBuildMCP `test_sim`: `LiveLoadAutoregulationTests` (9) + `LiveWorkoutAutoregulationTests` (9) + `CueEngineTests` (26) passed (44 total).

### Gate B (human, paired iPhone + Watch)

See `HANDOFF-V4M3.md` (D9–D12). D1–D8 unchanged from V4 M2.

### Human Xcode

- None for iOS (folder sync).

### Out of scope

- Google Calendar / EventKit (V4 M4)
- Auto-changing set weight without user tap
- Athlytic exertion score (V3 backlog)

### Files touched

| Area | Files |
|------|--------|
| Workout logic | `LiveLoadAutoregulation.swift` (new), `LiveWorkoutAutoregulation.swift` |
| Recovery | `RecoveryEngine.swift` |
| Train UI | `ActiveWorkoutView.swift`, `WorkoutExerciseSectionView.swift`, `WorkoutLiveSummaryBar.swift` |
| Tests | `LiveLoadAutoregulationTests.swift` (new), `LiveWorkoutAutoregulationTests.swift` |
| Handoff | `HANDOFF-V4M3.md` (new) |

---

## 2026-06-04 — V3 M5.1 Body Battery gauge complication

### Shipped

- **Snapshot:** `RecoveryWidgetSnapshot` adds `scoreValue`, `gaugeProgress` (0...1), and `gaugeTintColor` (green ≥70, orange 40 to 69, red below 40, matches watch `ContentView`).
- **Watch:** Second WidgetKit configuration `BodyBatteryComplication` with display name **Body Battery**; `RecoveryGaugeComplicationView` uses `Gauge` + `.accessoryCircularCapacity` and center score label. **Recovery** circular and rectangular complications unchanged.
- **Refresh:** `WatchComplicationRefresh` reloads both `RecoveryComplication` and `BodyBatteryComplication` kinds; log line mentions `recovery+bodyBattery`.
- **SDK note:** `WidgetFamily.accessoryGauge` is not in watchOS 26 / iOS 26 SDK. Gauge slots use `accessoryCircular` with `Gauge` and `.accessoryCircularCapacity` (documented WidgetKit pattern). iOS Lock Screen gauge family skipped (no separate accessory gauge family on iPhone).

### Field report — WidgetRenderer_Default watchdog (simulator)

**Symptom:** `com.apple.chrono.WidgetRenderer-Default` SIGKILL `0x8BADF00D` after 10s `scene-update` while previewing widgets in Simulator.

**Mitigation (agent):** Removed `containerBackground` + `EmptyView` gauge label from `RecoveryGaugeComplicationView` (minimal `Gauge` + tint only). If previews still hang, quit Simulator, run one scheme at a time, avoid Lock Screen widget gallery while tests run.

### Gate A (agent)

- `xcodebuild -scheme "SignalWatch Watch App" -destination 'platform=watchOS Simulator,id=93C9FE74-661C-43E7-BCEE-644772C166F4' build` **passed** (includes embedded watch app + widget extension).
- `SignalTests/WatchPayloadTests` **not re-run** in agent shell (DerivedData lock, then sim boot timeout). Logic changes are snapshot-only; re-run locally: `./scripts/build-and-test.sh` with `-only-testing:SignalTests/WatchPayloadTests`.

### Gate B (human, paired iPhone + Watch)

1. `./scripts/install-watch-app.sh`
2. iPhone: Signal → Dashboard (recovery loads).
3. Watch: long-press face → Edit → complication slot under the time (gauge / semicircle on Contour).
4. Choose **Body Battery** (not **Recovery**).
5. Pass criteria:

| ID | Test | Pass |
|----|------|------|
| G1 | Gauge slot visible | **Body Battery** appears in semicircle / gauge slot |
| G2 | Score match | Arc fill + center number match iPhone Dashboard recovery |
| G3 | Waiting | Before first sync: empty arc, center **—**, no crash |
| G4 | Refresh | Dashboard pull refresh; gauge updates within ~1 min |

Console: `category:watch` on iPhone and watch (`watch complication reload recovery+bodyBattery`).

### Human Xcode

Add to **SignalWatch Widget Extension** target if not compiling:

- `SignalWatch Widget Extension/RecoveryGaugeComplicationView.swift`

Ensure existing shared files remain on the extension target: `RecoveryWidgetSnapshot.swift`, `WatchPayloadCache.swift`, `WatchPayload.swift`.

### Out of scope

- Separate body battery drain algorithm (recovery score only)
- `WidgetFamily.accessoryCorner` curved label follow-up
- iOS Lock Screen gauge (no SDK family)
- V4 M4 EventKit

### Files touched

| Area | Files |
|------|--------|
| Shared | `RecoveryWidgetSnapshot.swift`, `WatchComplicationRefresh.swift` |
| Watch widget | `RecoveryComplicationWidget.swift`, `RecoveryGaugeComplicationView.swift` (new) |
| Tests | `WatchPayloadTests.swift` |

---

## 2026-06-04 — V4 M4 on-device calendar for coach and Train busy-day chip

### Shipped

- **EventKit store:** `CalendarEventStore` actor requests full calendar access, fetches events in an 8-day window (today plus 7).
- **Context builder:** `CalendarContextBuilder` assembles schedule summaries and a today-only **Busy day** chip title using meeting-before-5pm and total-event heuristics.
- **Coach:** `calendarSummary` section in `CoachContext`; `CalendarScheduleTool` registered on the FM session; access prompt on first chat send; `NSCalendarsFullAccessUsageDescription` in Info.plist.
- **Train UI:** Orange **Busy day** capsule above Start Workout when today meets busy heuristics.
- **Tests:** `CalendarContextBuilderTests` covers window filter, busy-day policy, summary assembly, and coach prompt section.

### Gate A (agent)

- `build_device` (Signal scheme, Cameron iPhone 16 Pro) **passed** (includes watch app + widget extension compile).
- `CalendarContextBuilderTests` and `WatchPayloadTests` **not re-run** on sim (user requested device build only).

### Gate B (human)

1. Open Signal on iPhone, send a Coach message; approve calendar access when prompted.
2. Train tab: confirm **Busy day** chip appears on a genuinely busy calendar day (or skip if calendar is light).
3. Ask Coach: "What does my schedule look like this week?" Confirm schedule-aware answer.

### Human Xcode

- Confirm `RecoveryGaugeComplicationView.swift` is on **SignalWatch Widget Extension** target (if watch gauge slot missing after install).
- EventKit calendar capability: verify **Calendars** is enabled on the Signal iOS target if access prompt never appears.

### Out of scope

- Google Calendar sync (on-device EventKit only)
- Writing or editing calendar events
- Busy-day chip refresh on foreground (loads on Train tab appear only)

### Files touched

| Area | Files |
|------|--------|
| Calendar | `CalendarEventStore.swift`, `CalendarContextBuilder.swift` (new) |
| Coach | `CalendarScheduleTool.swift`, `CoachContext.swift`, `CoachContextBuilder.swift`, `CoachSystemPrompt.swift`, `ChatViewModel.swift` |
| Train UI | `TrainHomeView.swift` |
| Logging | `Log.swift` |
| Plist | `Info.plist` |
| Tests | `CalendarContextBuilderTests.swift` (new) |

---

## 2026-06-04 — Coach/calendar sim test pass (3 rounds)

### Shipped

- **Round 0 (pre-test commit):** Event titles in schedule summaries, markdown headings, calendar prefetch on Coach tab, schedule-only coach rules.
- **Round 1:** Removed EventKit blocking from chat send (fixed 5x `ChatViewModelTests` timeout); `CoachQueryIntent` pins schedule when truncating context; `SchedulingCalendar` for Swift 6; markdown while streaming.
- **Round 2:** `Tomorrow:` day labels; suggestion chips send directly; resilient partial markdown; Train tab calendar prefetch; keyboard submit.
- **Round 3:** All-day before timed event sort; em dash removed from recent workout lines; `DailyBriefingComposer` notice flags use readiness detail over insight; submit guard while busy.

### Gate A (agent)

- iPhone 16 Pro sim (`20DDD35B-812A-49BE-9DCF-0685401ACC15`), `-parallel-testing-enabled NO` where noted.
- **Passed:** CalendarContextBuilderTests, CoachContextBuilderTests, ChatViewModelTests, ChatFeedbackTests, WatchPayloadTests, LiveWorkout/LiveLoad autoregulation, HevyImportPipelineGapTests, RAGRetrieverTests batch, DailyBriefingComposerTests (after fix).
- **Not run:** Full `SignalTests` suite (sim proc limit hit mid-session; cleaned with `pkill xcodebuild` + `simctl shutdown all`). FullImportIntegrationTests skipped.

### Gate B (human)

1. Reinstall on device; Coach tab: confirm calendar prompt on first open (not mid-send), suggestion chips send, `###` headings render.
2. Ask "What's on my calendar tomorrow?" Confirm event **title** appears.
3. Morning briefing notification: notice-level readiness should mention strain detail, not a random insight.

### Human Xcode

- None.

### Out of scope

- FullImportIntegrationTests re-run
- Push to remote (4 commits local ahead of origin)

### Files touched

| Area | Files |
|------|--------|
| Calendar | `CalendarContextBuilder.swift`, `SchedulingCalendar.swift` |
| Coach | `CoachContext.swift`, `CoachQueryIntent.swift`, `CoachContextBuilder.swift`, `CoachSystemPrompt.swift`, `ChatViewModel.swift`, `ChatView.swift`, `CoachMessageFormatting.swift` |
| Train | `TrainHomeView.swift` |
| Notifications | `DailyBriefingComposer.swift` |
| Tests | `CalendarContextBuilderTests.swift`, `CoachContextBuilderTests.swift`, `CoachMessageFormattingTests.swift` |

---

## 2026-06-05 — Watch deploy path, complication data fix, inline designs

### Shipped

- **Deploy checklist** in `scripts/install-watch-app.sh` header (USB iPhone, watch tunnel up, build Signal, devicectl to watch, iPhone Dashboard refresh, open SignalWatch once).
- **Picker vs live fix:** widget timelines call `WatchPayloadCache.readPayloadHydratingFromSession()` so complications read App Group or last `WCSession.receivedApplicationContext` (picker preview still uses `.preview`; live uses real data).
- **Utility large (accessoryInline):** Recovery supports inline; new **Recovery Battery** inline complication (battery SF Symbol + score).
- **Body Battery** remains circular gauge only (corners / ring slots). Utility large cannot render a gauge arc in WidgetKit inline family.
- **Watch app:** `SignalWatchApp` calls `receiver.activate()` on appear (WCSession on watch).

### Gate A (agent)

- `xcodebuild` Signal to iPhone **passed**.
- `./scripts/install-watch-app.sh` **passed** (watch `com.cameronro.Signal.watchkitapp` installed).

### Gate B (human)

1. Xcode Devices: watch tunnel **connected** before install.
2. iPhone Signal → Dashboard pull refresh.
3. Open SignalWatch on wrist once.
4. Utility face: large bottom slot → **Recovery** (score + HRV text) or **Recovery Battery** (icon + score). Corner circles → **Body Battery** for ring gauge.
5. Confirm live complication matches Dashboard (not "Waiting for Signal") after steps 2–3.

### Human Xcode

- None if `RecoveryInlineComplicationWidgets.swift` syncs via widget extension folder (file system synchronized group).

### Out of scope

- AppIntent style picker for inline designs (separate widget kinds instead)
- True gauge in Utility large inline slot (platform limitation)

### Files touched

| Area | Files |
|------|--------|
| Scripts | `install-watch-app.sh` |
| Shared | `WatchPayloadCache.swift`, `WatchComplicationRefresh.swift` |
| Watch widget | `RecoveryComplicationWidget.swift`, `RecoveryGaugeComplicationView.swift`, `RecoveryInlineComplicationWidgets.swift` (new) |
| Watch app | `SignalWatchApp.swift` |

---

## 2026-06-05 — V4 M1 live Train HR repair

### Shipped

- **iPhone pending telemetry:** `LiveWorkoutOutboundQueue` stores `sessionStart` / `sessionStop` when WCSession is not ready or watch unavailable; `retryPendingOutboundTelemetry()` flushes on activation, watch state change, and app foreground (mirrors recovery `pendingScore` pattern).
- **Idempotent watch kickoff:** `ensureWatchWorkoutStarted` on `ActiveWorkoutView.onAppear` and from `beginWatchWorkout` (Train home still uses full handshake via `forceFullHandshake`).
- **HK-first race:** Watch flushes buffered HR when `sessionKey` binds after `startWatchApp` or on `sessionStart` if session already running.
- **Logging:** `live HR bpm=` promoted to **info** for Gate B Console filter `category:workout`.

### Root cause (agent)

1. `LiveWorkoutWatchBridge.send` logged "deferred" but **dropped** `sessionStart` when WCSession was not `.activated` (no queue; recovery had `pendingScore`).
2. `beginWatchWorkout` only from `TrainHomeView`; banner resume and re-entering active workout skipped watch handshake.
3. Watch `flushPendingHeartRate` required `sessionKey`; HK from `startWatchApp` could run first with `sessionKey: nil` and never flush buffered samples when `sessionStart` arrived.

### Gate A (agent)

- `test_sim`: `LiveWorkoutTelemetryTests` (5) + `LiveWorkoutOutboundQueueTests` (2) passed (7 total).
- `build_device` (iPhone 16 Pro `00008140-001E34E10A01801C`) succeeded.
- `./scripts/build-watch-sim.sh` succeeded (watch target compiles with session manager changes).

### Gate B (human, paired iPhone + Watch)

1. `./scripts/install-watch-app.sh`
2. Both devices unlocked. Test **fresh start** (Train → Start Workout) and **banner resume** into active workout.
3. Console: subsystem `com.cameronro.Signal`, `category:workout` and `category:watch`.
4. **D2:** Within ~30 s, iPhone summary bar shows BPM; logs include `live HR bpm=` (info).
5. **D3:** Watch shows **Train** + BPM (not recovery-only).
6. **D8:** Finish on iPhone; watch session ends; single HK workout on phone.

### Human Xcode

- None. `LiveWorkoutOutboundQueue` lives in `LiveWorkoutWatchBridge.swift` (folder sync; no separate file to add to target).

### Follow-up fix (2026-06-05) — "Health access not set up on watch"

**Root cause:** `WatchApp-Info.plist` existed on disk but was **not** set as `INFOPLIST_FILE` on the SignalWatch Watch App target (`GENERATE_INFOPLIST_FILE` only). `WatchHealthKitAuthorization.isConfiguredForHealthKit` read empty usage strings from the built bundle.

**Fix:** `INFOPLIST_FILE = "SignalWatch Watch App/WatchApp-Info.plist"` on watch Debug/Release in `project.pbxproj`. Rebuilt and reinstalled via `./scripts/install-watch-app.sh`.

**After install:** Open SignalWatch on wrist; accept Health prompt when Train starts. If no prompt, delete watch app and reinstall script once.

### Out of scope

- V4 M2+ cues, workout complications, cloud
- `transferUserInfo` fallback for watch `heartRateBatch` (retry only if D2 fails with both apps foreground)

### Files touched

| Area | Files |
|------|--------|
| iPhone bridge | `LiveWorkoutWatchBridge.swift` (`LiveWorkoutOutboundQueue` enum) |
| WCSession | `WatchConnectivityService.swift`, `RootView.swift` |
| Train UI | `ActiveWorkoutView.swift` |
| Watch session | `WatchLiveWorkoutSessionManager.swift` |
| Tests | `LiveWorkoutTelemetryTests.swift` |

## 2026-06-05 — V4 M5 live HR sources

### Shipped

- **Source policy:** `LiveHeartRateSourcePolicy` picks watch when WCSession is supported, activated, paired, and watch app installed; otherwise phone HealthKit live session.
- **Phone fallback:** `LiveWorkoutPhoneSessionManager` runs iPhone `HKWorkoutSession` + `HKLiveWorkoutBuilder`, throttles BPM to the bridge (1 s), and **`discardWorkout()`** on stop so `HealthKitWorkoutWriter` remains the single save on finish.
- **Bridge branch:** `LiveWorkoutWatchBridge` locks source once per workout in `prepareLiveSession`, branches `ensureWatchWorkoutStarted` / `endWatchWorkout` by source; watch WCSession path unchanged.
- **UI:** `isLiveHeartRateRequested` reserves BPM column for phone path; neutral chip copy for phone ("Waiting for heart rate", "HR signal lost", "Health access needed for live HR").
- **Logging:** `live HR source=watch|phone` at session prepare; `live HR bpm=` includes `source=watch|phone`.

### Design (v1)

- Source locked at first `prepareLiveSession` for the workout; no mid-session flip if watch becomes available later.
- If WCSession is not yet `.activated` when Train starts, phone path is chosen even if watch would be ready seconds later.

### Gate A (agent)

- `test_sim` (pinned `id=20DDD35B-812A-49BE-9DCF-0685401ACC15`): `LiveHeartRateSourcePolicyTests` (6) + `LiveWatchHeartRateUITests` (7) + `LiveWorkoutTelemetryTests` including `LiveWorkoutOutboundQueueTests` (5+2) passed (18 total).
- `build_sim` succeeded (embeds watch target compile).

### Gate B (human)

1. **D2w / D3w / D8 (watch regression):** Paired watch + installed app. Train start: BPM on phone and watch within ~30 s; finish on phone yields single HK workout; watch session ends. Console `category:workout`, `live HR source=watch`.
2. **D2p (phone-only):** Unpair watch or remove watch app. Train start: BPM column appears; fills within ~60 s if HealthKit provides samples. Console `live HR source=phone`.
3. **D2a (AirPods):** No watch; AirPods Pro in ears during strength session. BPM updates on phone if Apple Health contributes HR to the phone workout session.
4. **D2n (no HR hardware):** No watch and no HR sensor: waiting chip, no crash.

### Human Xcode

- Add to **Signal** iOS target if folder sync did not pick them up: `LiveHeartRateSourcePolicy.swift`, `LiveWorkoutPhoneSessionManager.swift`, `LiveHeartRateSourcePolicyTests.swift`.

### Out of scope

- Watch-stale phone HK supplement, Hevy-style watch-only HK owner, complications, cloud, `.pbxproj` edits.

### Files touched

| Area | Files |
|------|--------|
| Policy | `LiveHeartRateSourcePolicy.swift` |
| Phone HK session | `LiveWorkoutPhoneSessionManager.swift` |
| Bridge | `LiveWorkoutWatchBridge.swift` |
| UI state | `LiveWatchHeartRateUI.swift` |
| Tests | `LiveHeartRateSourcePolicyTests.swift`, `LiveWatchHeartRateUITests.swift` |

---

## 2026-06-05 — V4 M2 Gate B (live HR cues + dynamic rest)

### Shipped

- **Gate B prep:** Fresh device build + iPhone install (`build_device`, `install_app_device`) and watch reinstall (`./scripts/install-watch-app.sh`, D1 pass: `Assets.car` present).
- **Set-cue diagnostics:** `WorkoutExerciseSectionView` logs `live HR set cue nudge=` when the HR line is composed, and `live HR set cue suppressed bpm= ageSeconds=` when a working set completes with no banner (stale or below threshold). Matches existing load-nudge log pattern for Console Gate B.

### Gate A (agent)

- `test_sim` (pinned `id=20DDD35B-812A-49BE-9DCF-0685401ACC15`): `LiveWorkoutAutoregulationTests` (9) + `CueEngineTests` (26) passed (35 total), run twice after diagnostic logging change.
- `build_device` (iPhone 16 Pro `00008140-001E34E10A01801C`) succeeded.

### Gate B (human, paired iPhone + Watch)

Prereq: M1 live HR (D2/D3) confirmed by user. iPhone app launched on device; watch app reinstalled. **Run D4–D8 below and tick Pass when done.**

Console filter: subsystem `com.cameronro.Signal`, category `workout`.

| ID | Test | Pass criteria | Agent | Human |
|----|------|---------------|-------|-------|
| **D1** | Watch install | `./scripts/install-watch-app.sh` OK; `Assets.car` in bundle | Pass | |
| **D2** | Live HR stream | BPM on summary bar within ~30 s; `live HR bpm=` logs | | Pass (assumed, M1) |
| **D3** | Watch workout UI | Watch **Train** + BPM during session | | Pass (assumed, M1) |
| **D4** | HR set cue | Working set, fresh BPM ≥150; banner includes `Heart rate still` line; log `live HR set cue nudge=` | | Pass (assumed) |
| **D5** | No HR cue | Stale/no BPM at set complete; tier only; log `live HR set cue suppressed` or no nudge log | | Pass (assumed) |
| **D6** | Dynamic rest | Auto-rest, HR ≥150, iPhone foreground; +30s twice max; amber `dynamicRestNotice`; log `dynamic rest extended seconds=30` | | Pass (assumed) |
| **D7** | Idle HR | Sit still until BPM &lt; 150; no further extensions | | Pass (assumed) |
| **D8** | Finish | Single HK workout on phone; watch session ends | | Pass (assumed) |

**D4 tips:** Summary bar must not show stale chip (`Watch HR signal lost`). Cues use 45 s freshness, not display BPM alone.

**D6 tips:** Keep iPhone foreground (`Timer.publish` pauses extensions when backgrounded). Expect extensions at ~1 s and ~21 s (20 s throttle).

### Field report (2026-06-05)

- Cameron: informal home smoke OK; full gym protocol (elevated HR working sets, dynamic rest loop) not run. **Accepted assumed pass** on D2–D8 per owner sign-off.
- **Milestone status:** Gate B closed (assumed). Revisit D4–D7 if gym session shows regressions.

### Human Xcode

- None.

### Out of scope

- V4 M3 load lines (D9–D12), calendar, complications, cloud
- Simulator fake HR

### Files touched

| Area | Files |
|------|--------|
| Train UI | `WorkoutExerciseSectionView.swift` (Gate B HR cue logs) |

---

## 2026-06-05 — Train keyboard resume

### Shipped

- **Root cause:** `SetRowView` called `commitFields()` on `scenePhase == .background` but left `@FocusState` focused, so `decimalPad` / `numberPad` stayed up and the active workout `List` often rendered blank after lock or app switch.
- **`SetRowView`:** On `.inactive` / `.background`, `commitFields()` then `focusedField = nil`; on `.active`, clear focus if still set. Keyboard **Done** toolbar dismisses focus (commits via existing focus `onChange`).
- **`ActiveWorkoutView`:** `.scrollDismissesKeyboard(.interactively)` on workout `List`; `TrainKeyboard.dismiss()` on inactive/background and on resume (`.active`).
- **`TrainKeyboard.swift`:** `TrainKeyboard.dismiss()` plus `TrainScenePhaseKeyboardPolicy` helpers.
- **Tests:** `TrainScenePhaseKeyboardPolicyTests` (3 cases).

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim` `-only-testing:SignalTests/TrainScenePhaseKeyboardPolicyTests`: 3 passed.

### Gate B (human)

1. Paired iPhone + Watch. Train live BPM (D2) OK baseline.
2. Active workout: tap weight or reps (pad up), switch app or lock 10+ s, return: workout list visible; keyboard gone or one-tap dismiss (Done / scroll).
3. Minimize workout (banner) → background → resume via banner: same pass.
4. Normal set logging: tap field → type → Done or complete set; values persist.
5. After background cycle, D2 live BPM still updates.
6. Background with partial entry: value committed (no data loss).

### Human Xcode

- Add to **Signal** iOS target if folder sync did not pick them up: `TrainKeyboard.swift`.
- Add to **SignalTests** if needed: `TrainScenePhaseKeyboardPolicyTests.swift`.

### Out of scope

- Watch, V4 M2/M3 cues, navigation rewrite, live HR bridge changes, cloud.

### Files touched

| Area | Files |
|------|--------|
| Train keyboard | `TrainKeyboard.swift` (new) |
| Set row | `SetRowView.swift` |
| Active workout | `ActiveWorkoutView.swift` |
| Tests | `TrainScenePhaseKeyboardPolicyTests.swift` (new) |

---

## 2026-06-05 — V4 M3 Gate B (D9–D12) device validation prep

### Shipped

- **Gate A:** `test_sim` on pinned iPhone 16 Pro sim: `LiveLoadAutoregulationTests` (9) + `LiveWorkoutAutoregulationTests` (9) + `CueEngineTests` (26) = 44 passed.
- **Device deploy:** `build_device` + `install_app_device` to iPhone `00008140-001E34E10A01801C`; watch app installed via `devicectl` to `A8077392-5F1A-5A0A-90F8-641502715165`.
- **Field fix:** `ActiveWorkoutView` reloads `sessionRecoveryScore` on `scenePhase == .active` (avoids stale score after background HK sync); logs `workout session recovery score=... chip=...` under `category:workout`.

### Gate A (agent)

- XcodeBuildMCP `test_sim`: 44 passed (load + HR autoregulation + cue engine).
- XcodeBuildMCP `build_device`: pass (Debug iphoneos).

### Gate B (human, paired iPhone + Watch)

Prereq: fresh build on device (done). Dashboard pull-to-refresh once; open SignalWatch on watch once. Console filter: `category:workout` and `category:recovery`.

| ID | Steps | Pass criteria |
|----|-------|---------------|
| **D9** | Dashboard recovery < 40; start strength workout; confirm `lowRecoveryChip` / **Low recovery day**; complete working set RPE ≤ 6 | Banner load line: `Recovery low. Hold weight.` (no Add); log `load autoregulation nudge=Recovery low. Hold weight.` |
| **D10** | Recovery ≥ 70; working set RPE ≤ 6, reps ≥ last session, `10 - rpe` ≥ profile target RIR (default 2) | Load line: `Easy set at target RIR. Add 2.5 kg next set.` |
| **D11** | Any recovery; working set RPE ≥ 9 | Load line: `RPE 9+. Stay at this weight for remaining sets.` |
| **D12** | Low recovery or grind; tier cue (RPE 7–8 on track or first RPE 9+); complete set while watch BPM ≥ 150 and sample < 45 s old | Banner order: tier, then `Heart rate still`, then load when applicable; logs `live HR set cue nudge=` and `load autoregulation nudge=` |
| **D8** | Finish workout after above | Single HK save; watch ends |

**D10 gotcha:** RPE 7+ or reps below last session blocks add nudge even on high recovery days.

**D12 gotcha:** If HR suppressed, Console shows `live HR set cue suppressed bpm=... ageSeconds=...`.

### Human Xcode

- None.

### Out of scope

- Policy rewrites; auto-mutating logged weight; simulator fake HR.

### Files touched

| Area | Files |
|------|--------|
| Train UI | `ActiveWorkoutView.swift` |
| Handoff log | `AGENT-BUILD-UPDATES.md` |

---

## 2026-06-05 — V3 M6 personal recovery baseline + disruptors

### Shipped

- **RecoveryDisruptorEpisode** SwiftData model (alcohol, trainingLoad, sleepDebt, illnessLike, unknown) with user tag and proxy inference.
- **PersonalReadinessCalculator** personal P25/median/P75 from 60-day scored history; calibrated at ≥21 days; recovery debt with kind-specific half-life and learned alcohol duration after 3+ user tags.
- **Dashboard** "Your norm" / delta, **Drank last night** tag + undo, personal status bands.
- **Train** personal P25/P75 bands when calibrated (chip: "Recovery below your norm" / "Recovering from last night"); fallback 70/40.
- **WatchPayload** optional `personalP25`, `personalP75`, `isCalibrated` (backward compatible).
- **Coach + Briefing** personal readiness summary and disruptor lines.
- **Reflection** `recoveryDisruptorActive`, `personalReadinessLow` insights with sleep/strain dedupe.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim`: 57 passed (`PersonalReadinessCalculatorTests`, `RecoveryDisruptorEngineTests`, `LiveLoadAutoregulationTests`, `RecoveryEngineTests`, `ReadinessFlagEvaluatorTests`, `WatchPayloadTests`, `DailyBriefingComposerTests`).
- `build_device` (iPhone `00008140-001E34E10A01801C`): pass.

### Gate B (human)

See `HANDOFF-V3M6.md` checklist R1–R6 (personal norm, alcohol tag, tag learning, proxy disruptor, calibrated Train, regression).

Console: `category:recovery`, `category:workout`.

### Human Xcode

- Add new Swift files to **Signal** and **SignalTests** targets (see `HANDOFF-V3M6.md`).
- Verify `RecoveryDisruptorEpisode` in schema; lightweight migration if existing store.

### Out of scope

- Athlytic exertion score, ACWR deload automation, Coach LLM disruptor RAG, complication layout changes, score formula change.

### Files touched

| Area | Files |
|------|--------|
| Models | `RecoveryDisruptorEpisode.swift` (new) |
| Recovery core | `RecoveryDisruptorHeuristics.swift`, `PersonalReadinessCalculator.swift`, `RecoveryDisruptorEngine.swift` (new); `RecoveryEngine.swift` |
| Train | `LiveLoadAutoregulation.swift`, `ActiveWorkoutView.swift`, `WorkoutExerciseSectionView.swift` |
| Dashboard | `DashboardViewModel.swift`, `DashboardRecoveryCard.swift`, `RecoveryDisruptorTagButton.swift` (new), `DashboardView.swift` |
| Watch | `WatchPayload.swift`, `WatchPayload+Signal.swift`, `WatchConnectivityService.swift`, `RecoveryWidgetSnapshot.swift`, `WatchRecoveryPushCoordinator.swift` |
| Reflection | `ReflectionSnapshot.swift`, `ReflectionSnapshotBuilder.swift`, `ReflectionRules.swift`, `ReflectionEngine.swift`, `InsightType.swift` |
| Coach / Briefing | `CoachContext.swift`, `CoachContextBuilder.swift`, `DailyBriefingComposer.swift`, `DailyBriefingScheduler.swift` |
| App | `ModelContainer+Signal.swift` |
| Tests | `PersonalReadinessCalculatorTests.swift`, `RecoveryDisruptorEngineTests.swift` (new); updates to `LiveLoadAutoregulationTests`, `WatchPayloadTests`, `DailyBriefingComposerTests`, reflection/recovery tests |
| Docs | `HANDOFF-V3M6.md` (new) |

---

## 2026-06-05 — V3 M7 exertion score + ACWR deload

### Shipped

- **Exertion score (0–100):** `ExertionScoreCalculator` blends 60% HR strain (session max vs personal 30d max HR and 60d RHR) with 40% volume (daily sets vs 28d chronic mean). RPE fallback when no HR (`meanRPE × 10`). Constants in `ExertionHeuristics`.
- **Exertion debt:** `ExertionDebtCalculator` rolling 7d sum normalized to personal P90 over 60d history (`exertionDebtNormalized` 0...1).
- **Personal readiness:** `adjustedReadinessPercentile` penalized up to 15 points when exertion debt is high; `LiveLoadAutoregulation` uses adjusted percentile for calibrated bands.
- **Training-load disruptor:** `RecoveryDisruptorEngine` fires on ACWR caution/overreach, exertion debt ≥ 0.7, or yesterday exertion ≥ personal P90 (replaces ACWR > 1.5 only).
- **Deload path:** `DeloadConditionEvaluator` (2 consecutive high-load days); `acwrDeloadSuggested` insight (ISO week dedupe, 3d expiry).
- **Train:** **High load week** chip (`deloadSuggestedChip`) on active workout; dismissible deload banner on Train home (ISO week keyed).
- **Dashboard:** **Strain this week: high vs your norm** footnote when debt high or deload active.
- **Coach + Briefing:** exertion/debt/ACWR lines in derived metrics; deload briefing line when `acwrDeloadSuggested` insight active; training-load disruptor copy mentions strain when debt high.
- **HK effort read:** `HealthKitEffortScoreReader` fetches `workoutEffortScore` by sample UUID when SwiftData RPE missing (`ExertionContextBuilder.buildAsync` for async enrichment; sync paths use RPE).
- **Compute-on-read:** no new SwiftData model; exertion fields on `DerivedMetricsSnapshot` and `ReflectionSnapshot` via `ExertionContextBuilder`.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass during builder session.
- Focused tests passed in builder session: `ExertionScoreCalculatorTests`, `ExertionDebtCalculatorTests`, `PersonalReadinessCalculatorTests`, `RecoveryDisruptorEngineTests`.
- Full `./scripts/build-and-test.sh` not run at handover (skipped per human request). Run before commit.

### Gate B (human)

1. After 2+ consecutive high-load days (ACWR caution/overreach or caution + debt ≥ 0.7), confirm **High load week** chip in Train and `acwrDeloadSuggested` in Insights.
2. Low-HRV user: exertion uses personal 30d max HR (check logs `category:recovery exertion score=`).
3. Finish workout with set RPE only (no watch HR): exertion uses RPE component.
4. Dashboard shows strain footnote when debt ≥ 0.7 or deload window active.
5. Morning briefing includes deload line only when `acwrDeloadSuggested` insight is active (not daily from debt alone).
6. Regression: V4 Train live HR, alcohol disruptor tag, watch recovery sync.

Console filter: `category:recovery`.

### Human Xcode

Add to **Signal** iOS target:

- `Data/Recovery/ExertionHeuristics.swift`
- `Data/Recovery/ExertionScoreCalculator.swift`
- `Data/Recovery/ExertionDebtCalculator.swift`
- `Data/Recovery/ExertionContextBuilder.swift`
- `Data/Recovery/DeloadConditionEvaluator.swift`
- `Data/Recovery/DeloadSuggestionReader.swift`
- `Data/HealthKit/HealthKitEffortScoreReader.swift`

Add to **SignalTests**:

- `ExertionScoreCalculatorTests.swift`
- `ExertionDebtCalculatorTests.swift`

Verify HealthKit read authorization includes `workoutEffortScore` if not already covered by existing workout write/share types.

### Out of scope

- `RecoveryScoreCalculator` HRV formula change; auto-reducing logged sets/weight; Coach LLM disruptor RAG; watch complication redesign; Google Calendar; persisted `DerivedMetric` SwiftData model (v1 is compute-on-read).

### Files touched

| Area | Files |
|------|--------|
| Exertion core | `ExertionHeuristics.swift`, `ExertionScoreCalculator.swift`, `ExertionDebtCalculator.swift`, `ExertionContextBuilder.swift`, `DeloadConditionEvaluator.swift`, `DeloadSuggestionReader.swift` (new) |
| HealthKit | `HealthKitEffortScoreReader.swift` (new) |
| Recovery | `PersonalReadinessCalculator.swift`, `RecoveryDisruptorEngine.swift`, `RecoveryDisruptorHeuristics.swift`, `RecoveryEngine.swift` |
| Derived | `DerivedMetricsService.swift` |
| Reflection | `ReflectionSnapshot.swift`, `ReflectionSnapshotBuilder.swift`, `ReflectionRules.swift`, `ReflectionEngine.swift`, `InsightType.swift` |
| Train | `WorkoutLiveSummaryBar.swift`, `ActiveWorkoutView.swift`, `TrainHomeView.swift`, `LiveLoadAutoregulation.swift` |
| Dashboard | `DashboardRecoveryCard.swift`, `DashboardViewModel.swift`, `DashboardView.swift` |
| Coach / Briefing | `CoachContextBuilder.swift`, `DailyBriefingComposer.swift`, `DailyBriefingScheduler.swift` |
| Diagnostics | `DiagnosticsViewModel.swift` |
| Tests | `ExertionScoreCalculatorTests.swift`, `ExertionDebtCalculatorTests.swift` (new); updates to `PersonalReadinessCalculatorTests.swift`, `RecoveryDisruptorEngineTests.swift`, `ReflectionEngineTests.swift`, `RecoveryEngineTests.swift`, `ReadinessFlagEvaluatorTests.swift` |
| Handoff log | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — V4 M4.5 Coach temporal grounding

### Shipped

- Runtime Clock in FM session instructions (`CoachClockFormatter` + `makeInstructions(referenceDate:)`) on every coach request; temporal semantics teach Health day vs Clock dayKey compare (no "past dates" wording).
- `getDeviceClock` zero-arg tool; four-tool budget: clock, calendarSchedule, exerciseHistory, muscleVolume.
- `FoundationModelsInferenceGate` in `FoundationModelsCoach` (serializes coach vs calendar alcohol FM).
- `HealthVectorRetriever` shared with Diagnostics: temporal window, recency ranking, pure cosine (coach k=4).
- Protein and health sync: reference-day-only `DailyNutrition`; `Health sync latest: YYYY-MM-DD.` when latest `DailyMetric` is more than one calendar day behind Clock.
- Schedule queries prefetch `calendarSummary`; others omit it. `calendarSchedule` tool takes `fromDayKey` / `toDayKey`.
- `ReflectionSnapshotBuilder` protein aligned to reference day.

### Gate A (agent)

- `build_sim`: pass.
- Targeted `test_sim` (15 tests): `CoachClockFormatterTests`, `HealthVectorRetrieverTests`, `DerivedMetricsProteinTests`, `CoachContextBuilderTests`, `RAGRetrieverTests`: all pass.

### Gate B (human)

1. Coach: "What day and time is it?" (match status bar).
2. After today's workout/sync, RAG may show `Health day <today>`; coach treats as today's data when dayKey matches Clock.
3. Stale HealthKit sync: coach cites freshness line, does not call stale day "today".
4. "How did I sleep last week?" uses temporal RAG window.
5. "What's on my calendar tomorrow?" via Schedule section or `calendarSchedule` tool with model-generated dayKeys.
6. No concurrent FM crash with calendar alcohol classifier during coach + disruptor overlap.

### Human Xcode

Confirm these are in the **Signal** target (PBXFileSystemSynchronizedRootGroup should pick them up automatically):

- `Data/Coach/CoachClockFormatter.swift`
- `Data/Coach/DeviceClockTool.swift`
- `Data/Coach/HealthVectorRetriever.swift`

Confirm in **SignalTests**:

- `CoachClockFormatterTests.swift`
- `HealthVectorRetrieverTests.swift`
- `DerivedMetricsProteinTests.swift`

### Out of scope

- Summarizer `Health day …` embedding format; multi-turn transcript; new FM tools (readiness, metricTrend, nutritionTotals); full sim test matrix.

### Files touched

| Area | Files |
|------|--------|
| Clock | `CoachClockFormatter.swift`, `DeviceClockTool.swift` (new) |
| Session | `CoachSystemPrompt.swift` |
| Coach | `FoundationModelsCoach.swift`, `CoachContextBuilder.swift`, `HealthVectorRetriever.swift` (new), `RAGRetriever.swift`, `CalendarScheduleTool.swift` |
| Calendar | `CalendarContextBuilder.swift` (`CalendarSummaryFormatter` window overload) |
| Metrics | `DerivedMetricsService.swift`, `ReflectionSnapshotBuilder.swift` |
| Diagnostics | `DiagnosticsRetrievalRunner.swift`, `DiagnosticsViewModel.swift` |
| Tests | `CoachClockFormatterTests.swift`, `HealthVectorRetrieverTests.swift`, `DerivedMetricsProteinTests.swift` (new); `CoachContextBuilderTests.swift`, `RAGRetrieverTests.swift` |
| Handoff log | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Apple Intelligence health check (FM device testing harness)

### Shipped

- Unified on-device **Apple Intelligence health check** in Diagnostics: sequential probes for model availability, inference gate, minimal generation, structured calendar classify, coach streaming, and tool roundtrip.
- Shared runner, grader, catalog, and JSON/pasteboard report (`fm_health_report` log line for Mac `log stream`).
- Sim grader unit tests (`FoundationModelsHealthGraderTests`).
- Device XCTest suite (`FoundationModelsHealthDeviceTests`) for USB-tethered automation.
- `scripts/run-fm-health-check.sh` wraps device build + `only-testing:SignalTests/FoundationModelsHealthDeviceTests`.

### Gate A (agent)

- `build_sim` pass.
- `test_sim -only-testing:SignalTests/FoundationModelsHealthGraderTests` pass (8/8).
- Device FM suite not run in agent session (requires Apple Intelligence on physical iPhone).

### Gate B (human, device)

1. Settings shows Apple Intelligence **Available**.
2. Diagnostics → **Apple Intelligence health check** → Run health check → all probes PASS or REVIEW (no FAIL).
3. Copy report and confirm pasteboard includes probe verdicts.
4. `./scripts/run-fm-health-check.sh` with iPhone on USB unlocked → XCTest pass.
5. Optional: `log stream --device --predicate 'subsystem == "com.cameronro.Signal" AND category == "coach"'` shows `fm_health_report json=...` during run.

### Human Xcode

Confirm in **Signal** target (PBXFileSystemSynchronizedRootGroup):

- `Features/Diagnostics/FoundationModelsHealthCatalog.swift`
- `Features/Diagnostics/FoundationModelsHealthGrader.swift`
- `Features/Diagnostics/FoundationModelsHealthReport.swift`
- `Features/Diagnostics/FoundationModelsHealthRunner.swift`

Confirm in **SignalTests**:

- `FoundationModelsHealthGraderTests.swift`
- `FoundationModelsHealthDeviceTests.swift`

### Out of scope

- Cloud model comparison or runtime network diagnostics.
- FM weight injection or custom model swap.
- Simulator FM inference (sim stays mock/grader-only).

### Files touched

| Area | Files |
|------|--------|
| FM harness | `FoundationModelsHealthCatalog.swift`, `FoundationModelsHealthGrader.swift`, `FoundationModelsHealthReport.swift`, `FoundationModelsHealthRunner.swift` (new) |
| Diagnostics UI | `DiagnosticsView.swift`, `DiagnosticsViewModel.swift` |
| Tests | `FoundationModelsHealthGraderTests.swift`, `FoundationModelsHealthDeviceTests.swift` (new) |
| Script | `scripts/run-fm-health-check.sh` (new) |
| Handoff log | `AGENT-BUILD-UPDATES.md` |
