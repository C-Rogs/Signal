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

## 2026-06-05 — In-workout exercise swap (Signal-guided)

### Shipped

- **Swap with Signal** on active workout exercise menu: constraint text, FM pick from ranked catalog shortlist, set prescription with progression intent, Apply swap or Pick manually.
- `ExerciseSwapCandidateRanker` filters by movement pattern, muscles, equipment constraints, history, picker defaults (max 8).
- `ExerciseSwapLoadPrescription` preserves remaining set structure, applies hold/increase/deload intent from last-session comparison and recovery.
- `WorkoutSwapFMSelector` structured FM selection with ranker fallback when model unavailable or pick invalid.
- `LiveWorkoutStore.swapExercise` rebuilds uncompleted sets; manual **Replace exercise** now uses same prescription path.

### Gate A (agent)

- `test_sim` (8 tests): `ExerciseSwapCandidateRankerTests`, `ExerciseSwapLoadPrescriptionTests`, `LiveWorkoutStoreSwapTests`, `WorkoutSwapFMSelectorTests` pass.
- `build_sim` pass.

### Gate B (human, device)

1. Start a live workout with Barbell Bench Press prefilled.
2. Exercise menu → **Swap with Signal**.
3. Type *bench is occupied* → **Suggest** → sensible substitute with set preview.
4. **Apply swap** updates exercise row and weights; **Pick manually** still works.
5. With completed working sets, confirm dialog appears before swap.

### Human Xcode

Confirm in **Signal** target:

- `Data/Workout/ExerciseSwapCandidateRanker.swift`
- `Data/Workout/ExerciseSwapLoadPrescription.swift`
- `Data/Workout/WorkoutSwapFMSelector.swift`
- `Features/Train/WorkoutSwapSheet.swift`

Confirm in **SignalTests**:

- `ExerciseSwapCandidateRankerTests.swift`
- `ExerciseSwapLoadPrescriptionTests.swift`
- `LiveWorkoutStoreSwapTests.swift`
- `WorkoutSwapFMSelectorTests.swift`

### Out of scope

- Main Coach chat swap commands.
- Cross-exercise e1RM translation without substitute history.
- Free-text workout logging.

### Files touched

| Area | Files |
|------|--------|
| Swap engine | `ExerciseSwapCandidateRanker.swift`, `ExerciseSwapLoadPrescription.swift`, `WorkoutSwapFMSelector.swift` (new) |
| Store | `LiveWorkoutStore.swift` |
| Train UI | `WorkoutSwapSheet.swift` (new), `WorkoutExerciseSectionView.swift` |
| Tests | `ExerciseSwapCandidateRankerTests.swift`, `ExerciseSwapLoadPrescriptionTests.swift`, `LiveWorkoutStoreSwapTests.swift`, `WorkoutSwapFMSelectorTests.swift` (new) |
| Handoff log | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Gemini workout paste import (Train M1)

### Shipped

- **Import workout** on Train home: paste Gemini-style text, preview catalog matches, start live session with prescribed sets.
- `GeminiWorkoutPasteParser` (pure Swift): title, exercises, kg/lb/DBs, RPE, warmup, coaching notes in parens.
- `LiveWorkoutStore.start(fromParsedPlan:)` + `addExercise(presetSets:)` bypasses `LastSessionAutofill` when sets are provided.
- `SetEntry.prescriptionNote` persisted for future Coach context (no Train row UI v1).
- Preview shows match badges, set summaries, optional manual catalog override via `ExercisePickerView`.

### Gate A (agent)

- `test_sim`: `GeminiWorkoutPasteParserTests` (18 cases) + `LiveWorkoutStoreTests` pass.
- `build_sim` pass (pinned iPhone 16 Pro sim).
- Build unblockers on same branch: `WorkoutSwapFMSelector` double-optional unwrap, `WorkoutSwapSheet` ViewBuilder fix.

### Gate B (human, device)

1. Copy Gemini export → Train → Import → Preview matches sample.
2. Start workout → `ActiveWorkoutView` shows kg, reps, RPE, warmup flags.
3. Complete a set → finish → HK write OK.
4. Catalog: lat pulldown, chest press, lateral raise match or manual pick works.

### Human Xcode

New files auto-sync via `PBXFileSystemSynchronizedRootGroup`; confirm in **Signal**:

- `Data/Workout/ParsedWorkoutPlan.swift`
- `Data/Workout/GeminiWorkoutPasteParser.swift`
- `Features/Train/GeminiWorkoutImportView.swift`
- `Features/Train/GeminiWorkoutImportPreviewView.swift`

Confirm in **SignalTests**:

- `GeminiWorkoutPasteParserTests.swift`

SwiftData: `SetEntry.prescriptionNote` added (lightweight migration on next launch).

### Out of scope

- Save parsed plan as routine with set templates.
- Coach reading `prescriptionNote`.
- Share sheet / Shortcuts import.
- Cardio set lines.

### Files touched

| Area | Files |
|------|--------|
| Parser | `ParsedWorkoutPlan.swift`, `GeminiWorkoutPasteParser.swift` (new) |
| Store | `LiveWorkoutStore.swift`, `LastSessionAutofill.swift`, `SetEntry.swift` |
| Backup | `BackupDTO.swift`, `BackupService.swift` |
| Train UI | `GeminiWorkoutImportView.swift`, `GeminiWorkoutImportPreviewView.swift` (new), `TrainHomeView.swift` |
| Tests | `GeminiWorkoutPasteParserTests.swift` (new), `LiveWorkoutStoreTests.swift` |
| Build fix | `WorkoutSwapFMSelector.swift`, `WorkoutSwapSheet.swift` |
| Docs | `HANDOFF-GEMINI-WORKOUT-IMPORT.md` (new), `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach M1 query router + intent-scoped context

### Shipped

- **`CoachQueryRouter`**: rule-based classifier with six routes (readiness, workoutPrescription, exerciseHistory, nutrition, schedule, general) and keyword scoring + tie-break.
- **`CoachContextScope`**: per-route context budget (RAG k, metrics parts, recovery, workouts, calendar).
- **Intent-scoped context**: nutrition omits ACWR/volume/workouts; workout prescription omits protein unless diet mentioned or deficit in data; readiness limits workout history to 1 session.
- **System prompt addenda** per route + instruction-level reasoning plan (Apple TN3193 Option A: step plan in instructions, single streaming pass, no invented APIs).
- **Logging**: `coach intent=... contextSections=... promptChars=...` in context builder and stream start.

### Gate A (agent)

- Coach Swift compiles (`CoachQueryRouter`, `CoachContextBuilder`, `CoachSystemPrompt`, `FoundationModelsCoach`).
- Full `build_sim` / `test_sim` **not run**: blocked by pre-existing compile error in `CoachMessageFormatting.swift` (unrelated `Font.Weight` comparison on this branch).
- Unit tests written: `CoachQueryRouterTests`, intent-scoping cases in `CoachContextBuilderTests`.

### Gate B (human, device)

1. Add `CoachQueryRouterTests.swift` to **SignalTests** if not auto-synced.
2. Fix `CoachMessageFormatting.swift` build error, then run `./scripts/build-and-test.sh`.
3. On iPhone 16 Pro: ask **"What should I train today?"** → answer cites ACWR/recovery, no protein paragraph unless Metrics shows deficit.
4. Ask **"Am I hitting protein?"** → cites protein/exertion, no ACWR lecture.
5. Confirm first-token latency still acceptable (<15s typical).

### Human Xcode

Confirm in **Signal**:

- `Data/Coach/CoachQueryRouter.swift` (new)

Confirm in **SignalTests**:

- `CoachQueryRouterTests.swift` (new)

### Out of scope

- Cloud Gemini fallback, fine-tuning, MLX LLM swap.
- Two-pass `respond` planning (Option B); kept single-pass for latency per TN3193 guidance.

### Files touched

| Area | Files |
|------|--------|
| Router | `CoachQueryRouter.swift` (new) |
| Context | `CoachContextBuilder.swift`, `CoachContext.swift` |
| Intent | `CoachQueryIntent.swift` |
| Prompt / session | `CoachSystemPrompt.swift`, `FoundationModelsCoach.swift` |
| Tests | `CoachQueryRouterTests.swift` (new), `CoachContextBuilderTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — P0 active workout blank screen fix

### Shipped

- **Root cause (videos + code):** SwiftUI `List` + `@FocusState` numpad in `SetRowView` left the active workout body blank while toolbar/session stayed alive (lock, app switch, in-app scroll/complete). Prior keyboard-only fix (same day) was insufficient.
- **`ActiveWorkoutView`:** Replaced workout `List` with `ScrollView` + `LazyVStack`; refresh surface `.id` on `scenePhase == .active`; `category:ui` appear/disappear/scenePhase logs.
- **Keyboard policy:** Dismiss keyboard only on `.inactive` / `.background` (removed resume `.active` `TrainKeyboard.dismiss()` that fought layout).
- **`SetRowView`:** Removed redundant focus clear on `.active`; long-press **Delete** context menu (swipe delete was List-only).
- **`WorkoutExerciseSectionView`:** VStack layout (no `Section` / `listRow*` modifiers).
- **`ActiveWorkoutContainerView`:** Keep cached session if reload misses (no flash/dismiss).
- **`TrainHomeView`:** Only clear nav `path` when `liveSessions` empty **and** `coordinator.activeSession == nil` (guards SwiftData query flicker).

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim` `TrainScenePhaseKeyboardPolicyTests` + `LiveWorkoutStoreTests`: 13 passed.

### Gate B (human, device, ~30 min gym sim)

1. Start or resume live workout with 3+ exercises.
2. Edit weight/reps (numpad up) → lock phone 10+ s → unlock: list visible, no blank body.
3. Repeat background via app switcher 3×; live BPM still updates each return.
4. Minimize (banner) → background → resume via banner: content visible.
5. Tab switch Dashboard ↔ Train 2× during live session: no blank requiring force-quit.
6. Complete a set, open RPE sheet, dismiss: list still populated.
7. Console: filter `category:ui` + `category:workout`; confirm `active workout appeared` / `scenePhase=active` with `exercises=N` (N > 0).

### Human Xcode

- No new files. Existing Train files auto-sync via `PBXFileSystemSynchronizedRootGroup`.

### Out of scope

- Exercise drag-reorder (removed with List; rare v1 path).
- Coach, import parser, watch bridge changes.

### Files touched

| Area | Files |
|------|--------|
| Active workout | `ActiveWorkoutView.swift`, `ActiveWorkoutContainerView.swift` |
| Exercise sections | `WorkoutExerciseSectionView.swift`, `WarmupSuggestionBannerView.swift` |
| Set row / keyboard | `SetRowView.swift`, `TrainKeyboard.swift` |
| Train home | `TrainHomeView.swift` |
| Tests | `TrainScenePhaseKeyboardPolicyTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — A7 exercise homepage (Hevy-style)

### Shipped

- **`TrainRoute.exerciseDetail(ExerciseDetailRoute)`** with `catalogID` + `exerciseTitle` fallback; `TrainHomeView.routeDestination` pushes `ExerciseDetailView` without popping active workout.
- **Entry taps:** `WorkoutHistoryDetailView` section headers and `WorkoutExerciseSectionView` exercise titles navigate via `NavigationLink`.
- **`ExerciseDetailView`:** Header (`ExerciseIllustrationView`, `MuscleChipRow`) + segmented **History** (last 10 sessions, RPE-aware set lines, link to `WorkoutHistoryDetailView`), **Progress** (e1RM `DashboardSparklineChart`, PR e1RM, PR load, avg working-set volume), **How-to** (numbered steps or empty state).
- **`HevyExerciseGuides.json`:** 104 how-to presets from owner `fixtures/HevyExport.csv` (115 distinct titles) matched to `free-exercise-db.json` instructions; `ExerciseGuideLoader` (bundled, no network).
- **Data helpers:** `ExerciseDetailHistoryLoader`, `ExerciseVolumeCalculator`, `ExerciseDetailViewModel`.
- **Regen script:** `scripts/build-hevy-exercise-guides.sh`.

**How-to preset count:** 104 exercises (11 Hevy export titles unmatched: Aerobics, Chest Fly variants, Chest Supported Y Raise, Diamond Push Up, Hip Abduction, Nordic Hamstrings Curls, Pilates, Push Up Close Grip, Reverse Fly Single Arm, Seated Cable Row V Grip, plus titles with no instruction match).

Sample presets: Bench Press (Barbell), Lat Pulldown (Cable), Incline Bench Press (Dumbbell), Shoulder Press (Machine Plates), Triceps Rope Pushdown, Squat (Barbell), Deadlift (Barbell). Full list in `Signal/Resources/HevyExerciseGuides.json`.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim` `ExerciseGuideLoaderTests`, `ExerciseVolumeCalculatorTests`, `ExerciseDetailHistoryLoaderTests`: 6 passed.

### Gate B (human, device)

1. Train → Recent → history → tap exercise name → detail → back returns to history.
2. Active workout → tap exercise name → detail → back returns to live session (not Train home).
3. Progress tab: e1RM chart when `ExerciseProgress` rows exist.
4. How-to tab: steps for Lat Pulldown (Cable) or Bench Press (Barbell).
5. Unknown guide exercise: How-to empty state, no crash.

### Human Xcode

Confirm in **Signal**:

- `Data/Workout/ExerciseGuideLoader.swift` (new)
- `Data/Workout/ExerciseDetailHistoryLoader.swift` (new)
- `Data/Workout/ExerciseVolumeCalculator.swift` (new)
- `Features/Train/ExerciseDetailView.swift` (new)
- `Features/Train/ExerciseDetailViewModel.swift` (new)
- `Resources/HevyExerciseGuides.json` (new, Copy Bundle Resources)

Confirm in **SignalTests**:

- `ExerciseGuideLoaderTests.swift` (new)
- `ExerciseVolumeCalculatorTests.swift` (new)
- `ExerciseDetailHistoryLoaderTests.swift` (new)

Touched: `LiveWorkoutCoordinator.swift`, `TrainHomeView.swift`, `WorkoutExerciseSectionView.swift`, `WorkoutHistoryDetailView.swift`, `DashboardChartValueStyle.swift`.

### Out of scope

- Exercise images, full catalog how-to, Coach deep links, watchOS, edit-from-detail.

### Files touched

| Area | Files |
|------|--------|
| Navigation | `LiveWorkoutCoordinator.swift`, `TrainHomeView.swift` |
| Detail UI | `ExerciseDetailView.swift`, `ExerciseDetailViewModel.swift` (new) |
| Data | `ExerciseGuideLoader.swift`, `ExerciseDetailHistoryLoader.swift`, `ExerciseVolumeCalculator.swift` (new), `HevyExerciseGuides.json` (new) |
| Entry taps | `WorkoutHistoryDetailView.swift`, `WorkoutExerciseSectionView.swift` |
| Charts | `DashboardChartValueStyle.swift` |
| Scripts | `scripts/build-hevy-exercise-guides.sh` (new) |
| Tests | `ExerciseGuideLoaderTests.swift`, `ExerciseVolumeCalculatorTests.swift`, `ExerciseDetailHistoryLoaderTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md`, `PARALLEL-AGENT-PLAN-2026-06-05.md` |

## 2026-06-05 — A6 history shows RPE

### Shipped

- **`WorkoutHistoryDetailFormatting`:** Testable helpers for strength/cardio set lines with optional ` · RPE N` suffix (`WorkoutRPEScale.compactLabel`), warmup omission, and session mean working-set RPE.
- **`WorkoutHistoryDetailView`:** Strength and cardio set rows show RPE when `set.rpe != nil` on working sets; header **Avg RPE** when any working set has RPE logged.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim` `WorkoutHistoryDetailFormattingTests`: 6 passed.

### Gate B (human, device)

1. Train → Recent → open session with Hevy import or live-logged RPE.
2. Each working set line shows `72.5 kg × 10 · RPE 8` (or equivalent) where data exists.
3. Warmup sets omit RPE even if stored.
4. Sets without RPE unchanged (no stray `RPE —`).
5. **Avg RPE** row appears when session has working-set RPE data.

### Human Xcode

Confirm in **Signal**:

- `Data/Workout/WorkoutHistoryDetailFormatting.swift` (new)

Confirm in **SignalTests**:

- `WorkoutHistoryDetailFormattingTests.swift` (new)

### Out of scope

- Exercise homepage (A7), inline RPE edit in history, model changes.

### Files touched

| Area | Files |
|------|--------|
| Formatting | `WorkoutHistoryDetailFormatting.swift` (new) |
| History UI | `WorkoutHistoryDetailView.swift` |
| Tests | `WorkoutHistoryDetailFormattingTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md`, `PARALLEL-AGENT-PLAN-2026-06-05.md` |

## 2026-06-05 — A6 history shows RPE

### Shipped

- **`WorkoutHistoryDetailFormatting`:** Testable helpers for strength/cardio set lines with optional ` · RPE N` suffix (`WorkoutRPEScale.compactLabel`), warmup omission, and session mean working-set RPE.
- **`WorkoutHistoryDetailView`:** Strength and cardio set rows show RPE when `set.rpe != nil` on working sets; header **Avg RPE** when any working set has RPE logged.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass.
- `test_sim` `WorkoutHistoryDetailFormattingTests`: 6 passed.

### Gate B (human, device)

1. Train → Recent → open session with Hevy import or live-logged RPE.
2. Each working set line shows `72.5 kg × 10 · RPE 8` (or equivalent) where data exists.
3. Warmup sets omit RPE even if stored.
4. Sets without RPE unchanged (no stray `RPE —`).
5. **Avg RPE** row appears when session has working-set RPE data.

### Human Xcode

Confirm in **Signal**:

- `Data/Workout/WorkoutHistoryDetailFormatting.swift` (new)

Confirm in **SignalTests**:

- `WorkoutHistoryDetailFormattingTests.swift` (new)

### Out of scope

- Exercise homepage (A7), inline RPE edit in history, model changes.

### Files touched

| Area | Files |
|------|--------|
| Formatting | `WorkoutHistoryDetailFormatting.swift` (new) |
| History UI | `WorkoutHistoryDetailView.swift` |
| Tests | `WorkoutHistoryDetailFormattingTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md`, `PARALLEL-AGENT-PLAN-2026-06-05.md` |

## 2026-06-05 — Train M1b paste import rest timers + parser hardening

### Shipped

- `GeminiWorkoutPasteParser` parses exercise rest (`Rest: 90s`, `Rest 2 min`, `(90s rest)`) and per-set rest between set lines.
- Set regex accepts optional `Set N:` prefix, unicode `×`, and bare `@7` RPE without `RPE` suffix.
- `ParsedExercise.restDurationSeconds` and `ParsedWorkoutSet.restDurationSeconds` flow into `WorkoutExercise` / `SetEntry` on `start(fromParsedPlan:)`.
- Auto-rest on set complete prefers per-set imported rest, then exercise default.
- Import preview shows `Rest 90s` per exercise (or per-set summary when rests differ).

### Gate A (agent)

- `xcodebuild test` pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`, derived data `/tmp/SignalM1bDD`: pass.
- `GeminiWorkoutPasteParserTests` (25 cases, 7 new): pass.
- `LiveWorkoutStoreTests.testStartFromParsedPlanAppliesRestDuration`: pass.

### Gate B (human, device)

1. Paste Gemini plan with `Rest 90s` after an exercise block → Preview shows **Rest 90s**.
2. Start workout → complete a set → floating rest bar counts down from imported duration (not default 90s when import says otherwise).
3. Optional: paste per-set rests (`Rest 60s` between sets) → first set complete uses 60s timer.

### Human Xcode

No new files. `SetEntry.restDurationSeconds` is a SwiftData model field; confirm lightweight migration or delete/reinstall if sim schema conflicts on upgrade.

### Out of scope

- Routine templates (Train M2).

### Files touched

| Area | Files |
|------|--------|
| Parser | `GeminiWorkoutPasteParser.swift` |
| Models | `ParsedWorkoutPlan.swift`, `SetEntry.swift` |
| Store | `LiveWorkoutStore.swift`, `LastSessionAutofill.swift` |
| UI | `GeminiWorkoutImportPreviewView.swift` |
| Backup | `BackupDTO.swift`, `BackupService.swift` |
| Tests | `GeminiWorkoutPasteParserTests.swift`, `LiveWorkoutStoreTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Catalog M1 staple exercises + Gemini import match rate

### Shipped

- `ExerciseTitleNormalizer` strips Gemini parentheticals, parses equipment-prefixed titles (`Dumbbell Lateral Raise`), and strips grip modifiers for fuzzy match.
- `CatalogAliasGenerator.geminiStyleAliases` maps staple Gemini names to catalog entries (machine chest press, lateral raise, cable triceps extension, bicep curl, lat pulldown).
- `ExerciseCatalogMatcher` fast-paths machine chest press and cable triceps extension; synonym tokens (bicep/biceps, extension/pushdown, chest/bench); review threshold raised to 0.7.
- Import preview auto-picks Review matches; **Change exercise** only on true Unmatched.
- Diagnostics **Catalog match report** for six Gemini sample titles.
- `ExerciseCatalogCurator` staple list expanded for machine press, triceps pushdown, bicep curl.

### Gate A (agent)

- `xcodebuild build-for-testing` pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`, derived data `.derivedDataDevice`: pass.
- `test-without-building` `ExerciseCatalogTests/geminiImportStapleTitlesMatchCatalog`: pass (retry after earlier sim Mach -308 aborts).
- `ExerciseCatalogTests/geminiImportStapleTitlesMatchCatalog` added (six user staple titles + equipment assertions).

### Gate B (human, device)

1. Paste user sample Gemini workout (lat pulldown, machine chest press, lateral raise, triceps, bicep curl).
2. Preview: ≥5/6 **Matched** or **Review** with catalog entry pre-selected; lateral raise, triceps, machine chest never **Unmatched** at 0 confidence.
3. **Change exercise** appears only on true Unmatched rows.
4. Diagnostics → **Catalog match report** shows six sample lines all matched or review.

### Human Xcode

No new files. Existing catalog Swift changes only.

### Out of scope

- Rest timer paste (Train M1b, other agent).
- Editing `free-exercise-db.json` (aliases cover naming gaps in matcher).

### Files touched

| Area | Files |
|------|--------|
| Matcher | `ExerciseCatalogMatcher.swift`, `ExerciseTitleNormalizer.swift` |
| Aliases / seed | `CatalogAliasGenerator.swift`, `ExerciseCatalogSeeder.swift` |
| Curator | `ExerciseCatalogCurator.swift` |
| Import UX | `GeminiWorkoutImportPreviewView.swift`, `ParsedWorkoutPlan.swift` |
| Diagnostics | `CatalogMatchReport.swift`, `DiagnosticsView.swift`, `DiagnosticsViewModel.swift` |
| Tests | `ExerciseCatalogTests.swift` |
| Collateral build fix | `CoachMessageFormatting.swift` (moved `applyParagraphStyle` before use) |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach M2 markdown in chat bubbles

### Shipped

- `CoachMessageFormatting` parses full markdown (`interpretedSyntax: .full`) with custom styling: `###` headings (semibold headline/title fonts), bullet and numbered lists (paragraph spacing), `**bold**`, inline and fenced code (monospace + `SurfaceElevated` background).
- `ChatAssistantBubble` takes `renderMarkdown` flag: completed assistant messages render attributed markdown; streaming and "Thinking..." show plain text to avoid broken partial headers.
- Removed bubble-level `.font(.body)` override on markdown `Text` so per-run heading and emphasis fonts apply.
- Five unit tests in `CoachMessageFormattingTests` (headings, bold numbers, bullet list, numbered list, inline code).

### Gate A (agent)

- `test_sim` `SignalTests/CoachMessageFormattingTests`: pass (5/5).
- App target compiles with updated `CoachMessageFormatting.swift` and `ChatView.swift`.

### Gate B (human)

1. On device, ask Coach a question that returns `###` sections and bullet lists (e.g. "How did I recover this week?").
2. Confirm headings render as styled text, not raw `###`.
3. Confirm bullets and **bold numbers** are readable on `Surface` in dark mode.
4. While streaming, text appears as plain characters; after completion, markdown styling appears.

### Human Xcode

No new files. Existing Swift only.

### Out of scope

- Coach M1 query router changes.

### Files touched

| Area | Files |
|------|--------|
| Formatting | `CoachMessageFormatting.swift` |
| Chat UI | `ChatView.swift` |
| Tests | `CoachMessageFormattingTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — P0 active workout blank screen (app switcher follow-up)

### Shipped

- **Root cause:** Opening app switcher is `scenePhase == .inactive`, not `.background`. Prior fix still ran keyboard/focus teardown + `tabViewBottomAccessory` relayout on inactive, blanking `NavigationStack` workout body while session stayed alive.
- **Keyboard policy:** Release set `@FocusState` only on `.background` (not `.inactive`). Removed `TrainKeyboard.dismiss()` from `ActiveWorkoutView`.
- **`isViewingActiveWorkout`:** Derived from Train `path` (active workout route), not `ActiveWorkoutView.onDisappear`.
- **`MainTabView`:** Freeze `tabViewBottomAccessory` while `scenePhase != .active`.
- **`ActiveWorkoutView`:** Pause 1s timer unless `.active`; removed ScrollView `.id` refresh; `VStack` not `LazyVStack`.
- **`ActiveWorkoutContainerView`:** Sync `onAppear` resolve (no `.task` re-entry).

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim): pass.
- `test_sim` `TrainScenePhaseKeyboardPolicyTests`: 2 passed.

### Gate B (human)

1. Active workout → open app switcher (stay on Signal card) → return: list visible.
2. Switcher → background another app → return: list visible.
3. Minimize + banner + switcher: same pass.

**Gate B result (2026-06-05):** Cameron device pass after `build_run_device`. App switcher + background cycles no longer blank active workout.

### Files touched

| Area | Files |
|------|--------|
| Keyboard | `TrainKeyboard.swift` |
| Active workout | `ActiveWorkoutView.swift`, `ActiveWorkoutContainerView.swift` |
| Tabs / nav | `MainTabView.swift`, `TrainHomeView.swift` |
| Tests | `TrainScenePhaseKeyboardPolicyTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach M1 hardening (router + context v2)

### Shipped

- Phrase-first overrides for UAT-shaped queries (recovery, protein, ACWR, calendar, deload).
- Word-boundary keyword matching; removed weak schedule-only temporal tokens (`today`, `tomorrow`).
- `CoachClassification` with scores + compound query detection (70% runner-up threshold).
- Compound scope merge (e.g. recovery + meetings → readiness context plus calendar).
- Route stored on `CoachContext`; classify once in builder, reused at inference.
- Nutrition route shows full protein status (on track / below / no log), not deficit-only.
- Route-filtered active insights by `InsightType`.
- Parallel RAG + calendar fetch when both needed.

### Gate A (agent)

- `build_device` pass on Cameron iPhone 16 Pro (~9–11s, no sim).

### Gate B (human, device)

1. Run Coach UAT smoke on device after install.
2. Spot-check Gate B queries from M1 spec.
3. Watch logs for `coach intent=... score=... compound=...`.

### Out of scope

- Sim test run (per human request).
- Two-pass FM planning.

### Files touched

| Area | Files |
|------|--------|
| Router | `CoachQueryRouter.swift` |
| Context | `CoachContextBuilder.swift`, `CoachContext.swift` |
| Coach | `FoundationModelsCoach.swift` |
| Tests | `CoachQueryRouterTests.swift`, `CoachContextBuilderTests.swift` |
| Log | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach settings toggles (M1 features)

### Shipped

- **Settings → Coach** section with three toggles (all default ON):
  - **Smart context routing:** intent-scoped context, insight filtering, intent addendum. OFF = legacy full context (RAG k=4, all metrics).
  - **Deep reasoning:** planning instruction in system prompt. OFF = skip for lower latency.
  - **Compound queries:** merge runner-up route context. OFF = primary route only. Disabled when smart context is off.
- `CoachFeatureFlags` reads UserDefaults from coach actor path (no MainActor hop).
- Logs include `smartContext=` and `deepReasoning=` on context build and stream start.

### Gate A (agent)

- `build_device` pass on Cameron iPhone 16 Pro (~12s).

### Gate B (human, device)

1. Profile → Settings → Coach: toggle each feature, ask a question, confirm behavior/latency.
2. With smart context OFF, protein question may include ACWR again (expected legacy).
3. With deep reasoning OFF, check first-token latency improves.

### Human Xcode

Confirm in **Signal**:

- `Core/Coach/CoachFeatureFlags.swift` (new)
- `Core/Coach/CoachPreferences.swift` (new)

Confirm in **SignalTests**:

- `CoachPreferencesTests.swift` (new)

### Out of scope

- Sim test run.

### Files touched

| Area | Files |
|------|--------|
| Preferences | `CoachFeatureFlags.swift`, `CoachPreferences.swift` (new) |
| Coach pipeline | `CoachContextBuilder.swift`, `CoachSystemPrompt.swift`, `FoundationModelsCoach.swift`, `CoachQueryRouter.swift` |
| Settings | `SettingsView.swift`, `SignalApp.swift` |
| Tests | `CoachPreferencesTests.swift` (new) |
| Log | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Train UI polish pass

### Shipped

- Shared Train chrome: `TrainChrome`, `TrainSectionHeader`, `TrainStatCard`, `TrainStatusChip` (Surface cards, OLED black backgrounds, consistent typography).
- **Train home:** ScrollView layout; filled Start + bordered Import; chip-based deload/busy; card routines/recent with empty CTAs.
- **Active workout:** Surface exercise cards; larger set numerics; 44pt complete/RPE/menu targets; summary chips unified.
- **Import:** Inline parse errors; card preview rows with match badges; bottom Start CTA.
- **Exercise detail / history:** `TrainStatCard`, monospaced history loads, scannable set rows with HR caption.
- **Sheets:** Log RPE, Exercise picker, Swap sheet aligned to Train chrome.
- **P0 preserved:** No keyboard dismiss on `.inactive`, no ScrollView `.id` refresh, `VStack` in active workout body, path-based `isViewingActiveWorkout`.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`): pass (~15s).
- `test_sim` `TrainScenePhaseKeyboardPolicyTests` + `GeminiWorkoutPasteParserTests`: 27 passed, 0 failed.

### Gate B (human, device)

1. Train home: start workout and import obvious in under 2s glance.
2. Active workout: log a set, rest timer visible, no blank on app switcher (regression).
3. Import preview: matched vs unmatched obvious; start workout works.
4. Exercise detail: tabs readable; back navigation OK from history and active workout.
5. OLED dark: true black backgrounds, no gray flash on push.

### Human Xcode

Add to **Signal** target if not auto-synced:

- `Features/Train/TrainChrome.swift`
- `Features/Train/TrainSectionHeader.swift`
- `Features/Train/TrainStatCard.swift`
- `Features/Train/TrainStatusChip.swift`

### Out of scope

- Navigation architecture, M2 routine templates, Dashboard/Coach/Profile, watch, new dependencies.

### Files touched

| Area | Files |
|------|--------|
| Shared chrome | `TrainChrome.swift`, `TrainSectionHeader.swift`, `TrainStatCard.swift`, `TrainStatusChip.swift` (new) |
| Home | `TrainHomeView.swift` |
| Active workout | `ActiveWorkoutView.swift`, `ActiveWorkoutContainerView.swift`, `WorkoutExerciseSectionView.swift`, `SetRowView.swift`, `SetTableHeaderView.swift`, `WorkoutLiveSummaryBar.swift`, `FloatingRestTimerBar.swift` |
| Import | `GeminiWorkoutImportView.swift`, `GeminiWorkoutImportPreviewView.swift` |
| Detail / history | `ExerciseDetailView.swift`, `WorkoutHistoryDetailView.swift` |
| Sheets | `LogSetRPEView.swift`, `ExercisePickerView.swift`, `WorkoutSwapSheet.swift` |
| Handover | `HANDOFF-TRAIN-UI-POLISH.md`, `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Train M3 haptics + rest timer bell

### Shipped

- Central `TrainFeedback` facade gating UIKit haptics and boxing bell on `TrainPreferences`.
- Duolingo-style haptics on set complete, PR celebration, rest start/end, 3-2-1 countdown, workout finish, primary taps, set-type selection, and dynamic rest extension warning.
- Boxing bell (`RestBell.caf`) plays when rest timer expires naturally (not on skip/finish).
- Settings toggles: **Workout haptics** and **Rest timer bell** (default ON).
- `RestTimerFeedbackEvaluator` detects rest start, countdown, expiry, and skip suppression.

### Gate A (agent)

- `build_sim` / `xcodebuild build` (pinned iPhone 16 Pro sim): **pass** (`BUILD SUCCEEDED`).
- `test_sim` `TrainPreferencesTests` + `RestTimerFeedbackEvaluatorTests`: **8 passed**, 0 failed.
- `./scripts/build-and-test.sh`: build pass; full sim test run hit simulator launch denial (`FBSOpenApplicationServiceErrorDomain`). Re-run tests via MCP or after `xcrun simctl shutdown booted` if needed.

### Gate B (human, physical iPhone 16 Pro)

1. Settings → Train: confirm **Workout haptics** and **Rest timer bell** toggles, both default ON.
2. Start workout → complete a working set: success haptic.
3. Log a PR-tier set (weight/reps beat last session): stronger celebration haptic.
4. Auto or manual rest start: light haptic.
5. Let rest count down: taps at 3, 2, 1 seconds.
6. Rest hits 0: success haptic + boxing bell.
7. Toggle bell OFF: haptic at end, no sound.
8. Toggle haptics OFF, bell ON: bell still plays.
9. Skip rest: primary tap only, no bell.
10. Finish workout: success haptic.

Console filter: `category:workout`.

### Human Xcode

Project uses synchronized root groups; verify these are in the **Signal** target (Copy Bundle Resources for audio):

- `Core/Train/TrainFeedback.swift`
- `Core/Train/TrainHapticEngine.swift`
- `Core/Train/RestBellPlayer.swift`
- `Core/Train/RestTimerFeedbackEvaluator.swift`
- `Resources/RestBell.caf`

### Out of scope

- watchOS haptics, Dashboard/Coach haptics, Core Haptics AHAP patterns, `.pbxproj` edits.

### Files touched

| Area | Files |
|------|--------|
| Core feedback | `TrainFeedback.swift`, `TrainHapticEngine.swift`, `RestBellPlayer.swift`, `RestTimerFeedbackEvaluator.swift` (new) |
| Prefs | `TrainPreferences.swift` |
| Settings | `SettingsView.swift` |
| Train UI | `ActiveWorkoutView.swift`, `WorkoutExerciseSectionView.swift`, `SetRowView.swift` |
| Cues | `CueEngine.swift` (`SetCueEvaluator.tier`) |
| Asset | `Resources/RestBell.caf` (new) |
| Tests | `TrainPreferencesTests.swift`, `RestTimerFeedbackEvaluatorTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — P1 performance and battery pass

### Shipped

- `ExerciseSessionHintCache` eliminates per-tick SwiftData `findLastExercise` scans during active workouts.
- `ActiveWorkoutRestTimerCoordinator` + layer isolate 1 Hz timer from exercise list invalidation.
- `WorkoutLiveSummaryBar` uses `TimelineView` for duration/HR staleness; volume/sets refresh on data change only.
- `reloadSessionRecoveryScore` removed from `onNeedsRefresh` hot path.
- `HealthKitManager` claims `isSyncing` before async work to prevent parallel sync races.
- Hot-path HR/rest/cue logs demoted to `.debug`.
- `retryPendingOutboundTelemetry` debounced (2s); `refreshDailyBriefingSchedule` throttled (15 min) on foreground.
- Audit doc: `PERF-AUDIT-2026-06.md`.

### Gate A (agent)

- `build_sim` (pinned iPhone 16 Pro sim): **pass**.
- `test_sim` `ExerciseSessionHintCacheTests` (3 tests): **pass** (proves zero refetch after warm).
- Full `SignalTests` via shell: **interrupted** (simulator clone/service hub failure after long run). Re-run `./scripts/build-and-test.sh` after `xcrun simctl shutdown booted` if needed.

### Gate B (human, physical iPhone 16 Pro)

1. Scripted workout 15–90 min: log sets, 2–3 rest timers, switcher 5×, lock screen during rest.
2. Settings → Battery → Signal: note energy impact vs pre-fix baseline (subjective OK).
3. Foreground thrash 10× in 2 min: confirm no duplicate `sync started` in Console (`category:sync`).
4. Watch paired live workout: confirm phone does not start `LiveWorkoutPhoneSessionManager` when source is watch.
5. P0 regression: no blank workout after switcher; keyboard resumes on return.

Agent ran `build_device` → `install_app_device` → `launch_app_device` on `00008140-001E34E10A01801C` (**pass**). Battery/scripted session validation remains human.

### Human Xcode

Verify new files in **Signal** + **SignalTests** targets if not auto-synced:

- `Data/Workout/ExerciseSessionHintCache.swift`
- `Features/Train/ActiveWorkoutRestTimerLayer.swift`
- `SignalTests/ExerciseSessionHintCacheTests.swift`

### Out of scope

- WC HR transport change, watch HK fallback, MLX unload, Dashboard reload refactor, `TrainHomeView` query limit, `.pbxproj` edits.

### Files touched

| Area | Files |
|------|--------|
| Hint cache | `ExerciseSessionHintCache.swift`, `LastSessionAutofill.swift` |
| Active workout | `ActiveWorkoutView.swift`, `ActiveWorkoutRestTimerLayer.swift`, `WorkoutExerciseSectionView.swift`, `WorkoutLiveSummaryBar.swift`, `WorkoutLiveSummary.swift` |
| HK sync | `HealthKitManager.swift` |
| Watch / logging | `LiveWorkoutWatchBridge.swift`, `LiveWorkoutPhoneSessionManager.swift`, `WatchLiveWorkoutSessionManager.swift` |
| Foreground | `RootView.swift` |
| Tests | `ExerciseSessionHintCacheTests.swift` |
| Docs | `PERF-AUDIT-2026-06.md`, `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach M2 multi-turn chat

### Shipped

- Reused `LanguageModelSession` across follow-ups when conversation memory is on; turn 1 loads full scoped context, turn 2+ sends user text only.
- Pinned thread route from turn 1; deep reasoning and full context build on turn 1 only.
- Context usage ring in Coach toolbar (~tokens / 4096); tap opens sheet with compact action.
- Near-limit banner and overflow messaging offer user-triggered compaction.
- `CoachThreadCompactor` summarizes transcript and seeds a new session with condensed summary (TN3193 pattern via instructions addendum).
- New conversation toolbar button resets thread and clears messages.
- Settings toggle **Conversation memory** (default on); off reverts to single-turn behavior per message.

### Gate A (agent)

- `build_device` (pinned iPhone 16 Pro `00008140-001E34E10A01801C`): **pass** (~9.5s).
- Sim tests: **not run** (per milestone plan).

### Gate B (human, physical iPhone 16 Pro)

1. Coach → "What should I train today?" → get prescription.
2. Follow-up: "Only 45 minutes, skip shoulders" → refines prior plan (does not ignore turn 1).
3. Context ring rises across turns; tap shows estimate.
4. At high fill, **Compact conversation** → ring drops; follow-up still coherent.
5. **New conversation** (toolbar) → ring resets; no memory of prior thread.
6. Settings → Conversation memory OFF → each message behaves like isolated Q&A.
7. Console: `coach thread=followUp`, `coach compact`, `contextTokens=…`.

### Human Xcode

Confirm new Swift files in **Signal** + **SignalTests** targets if PBXFileSystemSynchronizedRootGroup did not pick them up:

- `Core/Coach/CoachContextBudget.swift`
- `Data/Coach/CoachThreadTypes.swift`, `CoachTranscriptText.swift`, `CoachThreadCompactor.swift`
- `Features/Coach/CoachContextUsageRing.swift`
- `SignalTests/CoachContextBudgetTests.swift`, `CoachThreadCompactorTests.swift`

### Out of scope

- Chat persistence across app relaunch, live workout in Coach context, Start workout action, Diagnostics multi-turn, thumbs-down steering, proactive Coach tab nudge.

### Files touched

| Area | Files |
|------|--------|
| Thread engine | `LLMCoach.swift`, `FoundationModelsCoach.swift`, `CoachSystemPrompt.swift`, `CoachContext.swift` |
| Budget / transcript | `CoachContextBudget.swift`, `CoachThreadTypes.swift`, `CoachTranscriptText.swift`, `CoachThreadCompactor.swift` |
| Chat UI | `ChatViewModel.swift`, `ChatView.swift`, `ChatMessage.swift`, `CoachContextUsageRing.swift` |
| Settings | `CoachFeatureFlags.swift`, `CoachPreferences.swift`, `SettingsView.swift` |
| Diagnostics | `DiagnosticsViewModel.swift` (compactionFailed case) |
| Tests | `CoachContextBudgetTests.swift`, `CoachThreadCompactorTests.swift`, `CoachPreferencesTests.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — Coach context ring UX and calendar follow-up fix

### Shipped

- Context ring shows absolute token usage (`fractionUsed` from estimated / 4096); removed baseline-based `ringFractionUsed` and thread baseline token tracking.
- Ring tap target enlarged (28pt + inset padding) so stroke caps are not clipped in the Coach toolbar.
- Removed compact banner above chat input; **Compact conversation** appears only in the context usage sheet when near or over limit (emphasized when red).
- Context usage sheet lists breakdown rows (instructions, tools, turn 1 prompt, conversation, tool outputs) plus active tool names.
- Auto-compact on `contextTooLarge`: compacts thread once, inserts system notice bubble, retries the same query; logs `coach autoCompact reason=contextOverflow`.
- Calendar follow-up fix: schedule clarification detection (`isScheduleClarification`, `needsScheduleAccess`), tool refresh via transcript session swap when tool set changes, fresh calendar prefix on schedule follow-ups.

### Gate A (agent)

- `build_device` (pinned iPhone 16 Pro `00008140-001E34E10A01801C`): **pass** (~30.3s).
- Sim unit tests (20): `CoachContextBudgetTests`, `CoachContextBreakdownTests`, `CoachQueryIntentTests`, `CoachFollowUpToolsTests`, `ChatViewModelTests`, `ChatFeedbackTests`: **pass**.

### Gate B (human, physical iPhone 16 Pro)

1. Long thread with heavy turn 1: context ring reflects real high usage immediately (orange/red when appropriate).
2. No compact banner above input; compact only in ring sheet when near/over limit.
3. Ring not clipped on the left in the toolbar.
4. Tap ring: sheet shows breakdown rows including tools (e.g. `calendarSchedule`).
5. Force overflow on a long refinement thread: auto-compact note appears and follow-up succeeds.
6. Calendar: ask about events, then "what are the titles" returns titles without "Something went wrong".

### Human Xcode

Confirm new Swift files in **Signal** + **SignalTests** targets if PBXFileSystemSynchronizedRootGroup did not pick them up:

- `Core/Coach/CoachContextBreakdown.swift`
- `Data/Coach/CoachScheduleRefresh.swift`
- `SignalTests/MockLLMCoach.swift`, `CoachContextBreakdownTests.swift`, `CoachQueryIntentTests.swift`, `CoachFollowUpToolsTests.swift`

### Out of scope

- Proactive auto-compact before send when already over limit, chat persistence across relaunch, `.pbxproj` edits.

### Files touched

| Area | Files |
|------|--------|
| Context ring / sheet | `CoachContextUsageRing.swift`, `CoachThreadTypes.swift`, `ChatView.swift` |
| Breakdown | `CoachContextBreakdown.swift`, `CoachContextBudget.swift`, `FoundationModelsCoach.swift` |
| Auto-compact | `ChatViewModel.swift`, `ChatMessage.swift`, `LLMCoach.swift` |
| Calendar follow-up | `CoachQueryIntent.swift`, `CoachSystemPrompt.swift`, `CoachScheduleRefresh.swift`, `FoundationModelsCoach.swift` |
| Tests | `CoachContextBudgetTests.swift`, `CoachContextBreakdownTests.swift`, `CoachQueryIntentTests.swift`, `CoachFollowUpToolsTests.swift`, `ChatViewModelTests.swift`, `ChatFeedbackTests.swift`, `MockLLMCoach.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — P0 Train active workout blank screen (RootView overlay)

### Shipped

- Moved active workout presentation from `MainTabView.fullScreenCover` to a `RootView` `ZStack` overlay (`ActiveWorkoutShell`) so TabView/scenePhase does not own the workout hierarchy.
- `workoutSurfaceGeneration` on `LiveWorkoutCoordinator`; bumps on `presentWorkout` and on `scenePhase == .active` when workout is still presented (`refreshWorkoutSurfaceAfterForeground`) to force remount after background teardown.
- Removed `fullScreenCover` binding that called `minimizeWorkout()` on any dismiss (was conflating system teardown with user minimize).
- Diagnostics: `root scenePhase=…`, `refreshWorkoutSurface gen=…`, `activeWorkout disappear … scenePhase=… presented=…`.
- Tab switch no longer clears `isViewingActiveWorkout` when workout overlay is presented.

### Gate A (agent)

- `build_run_device` on iPhone 16 Pro `00008140-001E34E10A01801C`: **pass** (~65s).

### Gate B (human, physical iPhone 16 Pro)

1. Start workout with 2+ exercises. App switcher 3×, background 3×, tab switch 2× while workout open.
2. After each return: exercises visible (not blank toolbar). Live BPM still updates.
3. Profile → Copy workout debug log. Expect `refreshWorkoutSurface gen=N` after foreground; `disappear` on background is OK if `presented=true` and UI recovers.
4. Minimize → banner → Continue workout still works.
5. 30 min gym sim if prior steps pass.

### Human Xcode

Add to **Signal** target if not auto-synced:

- `Features/Train/ActiveWorkoutShell.swift`

### Out of scope

- Crash at `23:22:06 appLaunch` after background (needs separate repro if it persists).
- Stale `trainPath` routes (legacy nav path; overlay is source of truth now).

### Files touched

| Area | Files |
|------|--------|
| Overlay shell | `ActiveWorkoutShell.swift` |
| Coordinator | `LiveWorkoutCoordinator.swift` |
| Root | `RootView.swift` |
| Tabs | `MainTabView.swift` |
| Workout UI | `ActiveWorkoutView.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-05 — P0 Train blank screen follow-up (stale nav + silent dismiss)

### Shipped

- Log2: `disappear presented=false` without `minimizeWorkout` means `resetTrainNavigation` ran. `banner=false` afterward means no live session (finished/discarded), not minimized.
- Stale `TrainRoute.activeWorkout` pushed `EmptyView()` on Train nav stack (blank tab with no workout). Replaced with `StaleActiveWorkoutRouteView`.
- Container resolve failure no longer silently dismisses overlay; shows Retry.
- All dismiss paths log reason: `minimizeWorkout`, `resetTrainNavigation finishWorkout`, etc.
- Foreground refresh only after `workoutViewDisappearedWhilePresented`.

### Gate A (agent)

- `build_run_device` iPhone 16 Pro: **pass** (~19s).

### Gate B (human)

1. Train tab with no workout: never blank pushed screen.
2. Minimize/continue cycle shows Train home, not empty nav.
3. Dismiss events in log always include a reason string.

### Human Xcode

- `StaleActiveWorkoutRouteView.swift` if not auto-synced.

### Files touched

| Area | Files |
|------|--------|
| Coordinator | `LiveWorkoutCoordinator.swift` |
| Stale route | `StaleActiveWorkoutRouteView.swift`, `TrainHomeView.swift` |
| Container / shell / workout | `ActiveWorkoutContainerView.swift`, `ActiveWorkoutShell.swift`, `ActiveWorkoutView.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-06 — Train M2 routine templates with prescribed sets

### Shipped

- `RoutinePresetSet` SwiftData model mirrors `SetAutofillTemplate` (weight, reps, warmup, RPE, rest, prescription note).
- `RoutineExercise` extended with `restDurationSeconds`, `autoStartRestOnSetComplete`, `presetSets` relationship.
- `RoutineTemplateStore`: `createRoutine(name:from:)`, `presetTemplates(for:)`, `totalPresetSetCount(for:)`.
- `LiveWorkoutStore.start(from:)` uses routine presets when present; empty presets keep last-session autofill.
- `RoutineExerciseEditorView`: per-exercise sheet for rest + set editing (add/delete/reindex).
- `RoutineEditorView`: navigation to exercise editor, set count subtitle on rows.
- Gemini import preview: **Save as Routine** secondary CTA (name prompt, haptic, dismiss without starting workout).
- `TrainHomeView` routine rows show `N exercises · M sets` when presets exist.

### Gate A (agent)

- `build_device` iPhone 16 Pro `00008140-001E34E10A01801C`: **pass** (~18s).
- `install_app_device` + `launch_app_device`: **pass** (PID 9658).
- `RoutineTemplateStoreTests` (4 tests via `test_sim`): **pass**.

### Gate B (human)

- Agent verified build/install/launch on device.
- Human spot checks: paste Gemini sample → Save as Routine → start routine with prefilled sets; edit routine add set → start reflects change; P0 app switcher + keyboard resume on active workout from routine.

### Human Xcode

- Empty (synchronized root groups auto-include new Swift files; `RoutinePresetSet` registered in `ModelContainer+Signal.swift`).

### Out of scope

- Finished workout → routine, Coach integration, backup/export of routines, watch changes, P0 stability policy edits.

### Files touched

| Area | Files |
|------|--------|
| Models | `RoutinePresetSet.swift` (new), `Routine.swift` |
| Schema | `ModelContainer+Signal.swift` |
| Store | `RoutineTemplateStore.swift` (new), `LiveWorkoutStore.swift` |
| Editor | `RoutineExerciseEditorView.swift` (new), `RoutineEditorView.swift` |
| Import | `GeminiWorkoutImportPreviewView.swift`, `GeminiWorkoutImportView.swift` |
| Home | `TrainHomeView.swift` |
| Tests | `RoutineTemplateStoreTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-08 — P0 Train blank screen (Notification Centre + inactive return)

### Shipped

- Restored `SetRowView` keyboard policy: release `@FocusState` on `.background` only via `TrainScenePhaseKeyboardPolicy` (regression from overlay commit removed this handler).
- `LiveWorkoutCoordinator.handleRootScenePhaseChange`: remount workout surface on return to `.active` from `.inactive` or `.background`, plus `onDisappear` flag; logs `refreshWorkoutSurface reason=inactiveReturn|backgroundReturn|disappear|blankBodyDetected`.
- `ActiveWorkoutView.detectAndRecoverBlankBodyIfNeeded`: safety net when session has exercises but rendered list is empty.
- `MainTabView`: keep `tabViewBottomAccessory` branch stable when minimized workout banner applies; hide banner on `.inactive` via `isEnabled` / zero-height placeholder instead of removing accessory slot.
- Unit tests: `LiveWorkoutCoordinatorScenePhaseTests` (6 cases) + existing `TrainScenePhaseKeyboardPolicyTests`.

### Gate A (agent)

- `test_sim` `LiveWorkoutCoordinatorScenePhaseTests` + `TrainScenePhaseKeyboardPolicyTests`: **pass** (8/8, ~69s).
- `build_device` iPhone 16 Pro `00008140-001E34E10A01801C`: **pass** (~13s).
- `launch_app_device`: **pass** (PID 20859).

### Gate B (human, physical iPhone 16 Pro)

1. Active workout 15+ min with numpad use → pull Notification Centre ×5 → exercises visible each return.
2. App switcher ×3 and lock/unlock with numpad open: no blank body.
3. Profile → copy workout debug log: expect `refreshWorkoutSurface reason=inactiveReturn` after Notification Centre; `setRow releaseFocus` only on background.

### Human Xcode

- Empty if synchronized root groups picked up `LiveWorkoutCoordinatorScenePhaseTests.swift`.

### Out of scope

- Coach/Dashboard blank screens; launch-after-background crash noted in prior handover.

### Files touched

| Area | Files |
|------|--------|
| Keyboard | `SetRowView.swift` |
| Coordinator | `LiveWorkoutCoordinator.swift` |
| Root lifecycle | `RootView.swift` |
| Active workout | `ActiveWorkoutView.swift` |
| Tabs | `MainTabView.swift` |
| Tests | `LiveWorkoutCoordinatorScenePhaseTests.swift` (new) |
| Handover | `AGENT-BUILD-UPDATES.md` |

## 2026-06-08 — Production launch path (persisted store + upgrade install)

### Shipped

- **False positive:** Prior launch pass was after app delete (empty SwiftData). Upgrade install over existing data still hit scene-create watchdog.
- **Async store bootstrap:** `SignalApp` shows `AppLaunchShellView` on first frame, then loads `ModelContainer` in `.task` after scene exists. Preserved data survives; no `fatalError` on load failure (retry UI via `AppLaunchFailureView`).
- **Removed `tabViewBottomAccessory`:** Live workout banner uses `safeAreaInset` on all OS versions. Banner attaches only after `isLaunchShellReady` (post-first-frame) and when an active session exists.
- **Deferred data-quality migration:** `DataQualityMigration.scheduleIfNeeded` runs after yield, not during store open.

### Gate A (agent)

- `build_device` iPhone 16 Pro: **pass** (~11s).
- `install_app_device` over existing install (no delete): **pass**.
- `launch_app_device`: **pass** (PID 20965; alive and interactive after 28s; no watchdog).
- `test_sim` scene-phase tests: **pass** (8/8).

### Gate B (human)

- Cold launch with real workout history + optional in-progress session: dashboard or embedding gate, not immediate kill.
- Start workout, minimize, confirm banner above tab bar still works.

### Human Xcode

- Empty if synchronized groups picked up `AppLaunchShellView.swift`, `AppLaunchFailureView.swift`.

### Out of scope

- Explicit `SchemaMigrationPlan` for `RoutinePresetSet` (SwiftData lightweight migration only).

### Files touched

| Area | Files |
|------|--------|
| Bootstrap | `SignalApp.swift`, `AppLaunchShellView.swift` (new), `AppLaunchFailureView.swift` (new) |
| Tabs / banner | `MainTabView.swift` |
| Migration | `DataQualityMigration.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |


### Shipped

- **Root cause:** On iOS 26.1+, `MainTabView` always attached `tabViewBottomAccessory(isEnabled:)` even when no live workout banner was needed. Scene creation blocked the main thread ~20s; SpringBoard killed the process with `0x8BADF00D` (`scene-create watchdog transgression`). Reproduced on committed HEAD, not only blank-screen WIP.
- **Fix:** Only wrap `TabView` with `tabViewBottomAccessory` when `showsWorkoutBanner` is true (iOS 26.1+ matches pre-26.1 gating). When a banner is shown, still freeze visibility on `.inactive` via `isEnabled: tabBottomAccessoryVisible`.

### Gate A (agent)

- `build_device` iPhone 16 Pro `00008140-001E34E10A01801C`: **pass** (~12s).
- `install_app_device` + `launch_app_device`: **pass** (PID 20951; process still alive after 60s+; no watchdog in syslog).
- Prior launches (pre-fix): watchdog kill before `appLaunch` diagnostic.

### Gate B (human)

- Agent verified launch no longer dies immediately.
- Human spot check: cold launch from home screen; confirm dashboard loads; start workout and verify banner still appears above tab bar.

### Human Xcode

- Empty.

### Out of scope

- Blank-screen Gate B matrix (Notification Centre ×5) pending human pass on this build.

### Files touched

| Area | Files |
|------|--------|
| Tabs | `MainTabView.swift` |
| Handover | `AGENT-BUILD-UPDATES.md` |
