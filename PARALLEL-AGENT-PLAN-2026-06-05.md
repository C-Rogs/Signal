# Parallel agent plan — Gym stability, catalog, import, coach (2026-06-05)

Central coordination doc for **parallel implementation agents** (streams A1–A7). Owner: Cameron. Architect chat assigns workstreams; each agent reads this file first, claims a stream, updates **Status** before commit, appends results to `AGENT-BUILD-UPDATES.md` when done.

**Detailed handoffs:** A6 → `HANDOFF-TRAIN-HISTORY-RPE.md` · A7 → `HANDOFF-EXERCISE-HOMEPAGE.md`

**User evidence (blank screen):**

- `/Users/cameronro/Downloads/ScreenRecording_06-05-2026 19-02-47_1.mov`
- `/Users/cameronro/Downloads/ScreenRecording_06-05-2026 19-03-44_1.mov`

---

## Coordination rules

1. **Claim one stream** (A1–A7). Edit the Status table below: `IN PROGRESS — <agent/note>` before coding.
2. **Build lock (integrator):** Only **one** `build_sim` / `test_sim` / `xcodebuild` at a time on pinned sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`. Agents ship code; integrator runs Gate A sequentially. Kill stray builds before starting (`pkill -f "xcodebuild.*Signal"`). Shutdown booted sims after tests (`xcrun simctl shutdown booted`).
3. **Do not edit `.pbxproj` / entitlements.** List new Swift files for human target membership.
3. **Conflict zones** — coordinate before touching:
   | Files | Streams |
   |-------|---------|
   | `ActiveWorkoutView.swift`, `SetRowView.swift`, `TrainHomeView.swift`, `TrainKeyboard.swift` | **A1 only** (unless A1 merged) |
   | `ExerciseCatalogMatcher.swift`, `CatalogAliasGenerator.swift`, `ExerciseCatalogSeeder.swift`, `ExerciseCatalogCurator.swift` | **A2** (A3 may add matcher tests only after A2 lands or agree on branch order) |
   | `GeminiWorkoutPasteParser.swift`, `LiveWorkoutStore.swift`, import preview views | **A3** (wait for A2 if matcher API changes) |
   | `CoachContextBuilder.swift`, `CoachQueryIntent.swift`, `CoachSystemPrompt.swift`, `FoundationModelsCoach.swift` | **A4 only** |
   | `ChatView.swift`, `CoachMessageFormatting.swift`, `ChatMessageBubble` paths | **A5 only** |
   | `WorkoutHistoryDetailView.swift` | **A6 only** |
   | `TrainRoute`, `TrainHomeView` navigation, `ExerciseDetailView` (new), `WorkoutExerciseSectionView` title tap | **A7 only** (A6 may share history row formatting — coordinate) |
4. **Build:** MCP `build_sim` pinned sim `20DDD35B-812A-49BE-9DCF-0685401ACC15`; device gates on iPhone 16 Pro.
5. **On complete:** set Status to `DONE`, append section to `AGENT-BUILD-UPDATES.md`, output `MILESTONE COMPLETE: <stream id>, READY TO COMMIT`. Do not commit unless owner asks.
6. **Integration pass (human or integrator agent):** after claimed streams DONE, run full `./scripts/build-and-test.sh` + gym smoke (A1 Gate B) on device.

---

## Status

| ID | Stream | Priority | Status | Owner / branch |
|----|--------|----------|--------|----------------|
| **A1** | Train blank screen P0 | P0 | `DONE — integrator commit pending` | `40309465` |
| **A2** | Catalog completeness + matching | P1 | `DONE — integrator commit pending` | `f81ecd55` |
| **A3** | Gemini import rest timers + parser | P2 | `DONE — integrator commit pending` | `381d1d5d` |
| **A4** | Coach router + intent context | P2 | `DONE — integrator commit pending` | `b4b7a5d1` |
| **A5** | Chat markdown rendering | P2 | `DONE — integrator commit pending` | `208ccf67` |
| **A6** | History shows RPE | P2 | `DONE — integrator commit pending` | `73a2d68b` |
| **A7** | Exercise homepage (Hevy-style) | P3 | `DONE — integrator commit pending` | `908b4a34` |

**Merge order if rebasing:** A1 → A2 → A3 → (A4 ∥ A5) → A6 → A7.

**Roadmap note:** V2 M2 mentions inline e1RM/last-time in the logger, not a dedicated exercise screen. **A6/A7 are not covered by a later milestone** — build unless owner defers.

---

## Shared context

- **Blank screen:** Prior `TrainKeyboard` + focus fix (2026-06-05) insufficient. User cannot test gym features.
- **Import sample failures:** Machine Chest Press, Dumbbell Lateral Raise, Cable Triceps Extension unmatched; Lat Pulldown and sometimes Bicep Curl matched.
- **Coach:** On-device Foundation Models ≠ cloud Gemini. Router + lean context > bigger prompt.
- **Prerequisites shipped:** V4 M1–M3 Train, V3 M6 personal recovery, Gemini paste import v1 (`HANDOFF-GEMINI-WORKOUT-IMPORT.md`).

---

# Stream A1 — Train blank screen (P0)

## Task

Fix active workout UI going **blank** after backgrounding, tab switch, or **while staying in Signal**. Gym blocker.

## Repro targets

1. Active workout → numpad on set field → lock / switch app → return blank.
2. Active workout → scroll / complete set / sheet → blank without leaving app.
3. Minimize via banner → resume.
4. Tab Dashboard ↔ Train during live session.
5. Session may still be alive (watch BPM OK) while UI blank.

## Suspects

- `List` + `@FocusState` in `SetRowView`; `TrainKeyboard.dismiss()` on every `.active` in `ActiveWorkoutView`.
- `ActiveWorkoutContainerView` session resolution; `TrainHomeView` path clearing on `liveSessions` change.
- Sheets: RPE, import, add exercise.

## Key files

- `Signal/Features/Train/ActiveWorkoutView.swift`
- `Signal/Features/Train/SetRowView.swift`
- `Signal/Features/Train/ActiveWorkoutContainerView.swift`
- `Signal/Features/Train/TrainHomeView.swift`
- `Signal/Features/Train/TrainKeyboard.swift`

## Approach

1. Review user screen recordings.
2. Add `category:ui` / `category:workout` logging on appear, scenePhase, path, sessionID.
3. Minimal fix; consider `ScrollView` + `LazyVStack` instead of `List` if List is root cause.

## Gate B

30 min gym flow: log sets, background 3×, tab switch 2×, no restart required. Live BPM regression OK.

## Out of scope

Catalog, import parser, coach, markdown.

---

# Stream A2 — Catalog completeness + matching

## Task

Raise import match rate for common Gemini names; expand staples in picker catalog.

## User failures

| Exercise | Was |
|----------|-----|
| Wide-Grip Lat Pulldown | Matched |
| Machine Chest Press | Unmatched |
| Dumbbell Lateral Raise | Unmatched |
| Cable Triceps Extension | Unmatched |
| Dumbbell Bicep Curl | Matched / flaky |

## Goals

1. Audit `free-exercise-db.json` + `ExerciseCatalogCurator` for machine chest press, lateral raise, cable triceps, dumbbell curl.
2. Expand `ExerciseCatalogSeeder` / `CatalogAliasGenerator` aliases for Gemini-style titles (strip parentheticals).
3. `ExerciseCatalogMatcher`: equipment synonyms, wide-grip, review band for score 0.7–0.82.
4. Import preview: auto-pick high confidence; "Change exercise" only when needed.

## Key files

- `Signal/Data/Catalog/ExerciseCatalogMatcher.swift`
- `Signal/Data/Catalog/ExerciseCatalogSeeder.swift`
- `Signal/Data/Catalog/CatalogAliasGenerator.swift`
- `Signal/Data/Catalog/ExerciseCatalogCurator.swift`
- `Signal/Features/Train/GeminiWorkoutImportPreviewView.swift` (match UX only)

## Gate A

Matcher unit tests for all six user exercise names.

## Gate B

User sample import: ≥5/6 auto-match or one-tap pick.

## Out of scope

Rest timer parsing (A3).

---

# Stream A3 — Gemini import rest timers + parser hardening

## Task

Extend paste import for **rest durations** and looser set-line formats.

## Prerequisites

- `GeminiWorkoutPasteParser`, `LiveWorkoutStore.start(fromParsedPlan:)` shipped.
- Prefer A2 merged first if matcher signatures change.

## Goals

1. Parse rest lines: `Rest: 90s`, `Rest 2 min`, `(90s rest)` between exercises → `WorkoutExercise.restDurationSeconds`.
2. Tolerate `×` vs `x`, optional `Set N:`, `@7` without `RPE`.
3. Preview shows rest per exercise; auto-rest uses imported value.

## Key files

- `Signal/Data/Workout/GeminiWorkoutPasteParser.swift`
- `Signal/Data/Workout/ParsedWorkoutPlan.swift` (if separate)
- `Signal/Data/Workout/LiveWorkoutStore.swift`
- `Signal/Features/Train/GeminiWorkoutImportPreviewView.swift`
- `SignalTests/GeminiWorkoutPasteParserTests.swift`

## Gate B

Paste plan with rests → start → complete set → `FloatingRestTimerBar` uses imported seconds.

## Out of scope

Routine templates (Train M2).

---

# Stream A4 — Coach router + intent-scoped context

## Task

Route queries by intent; stop sending nutrition context on workout questions; explore deeper on-device reasoning within FM limits.

## Current state

- `CoachQueryIntent`: keyword flags (schedule, history, volume, off-topic, clinical).
- `CoachContextBuilder` loads RAG, metrics, workouts for **every** query.
- `LanguageModelSession` + `.default`, single stream.

## Goals

1. **`CoachQueryRouter`**: `.readiness`, `.workoutPrescription`, `.exerciseHistory`, `.nutrition`, `.schedule`, `.general` (rule-based, tested).
2. **Intent-scoped context** in `CoachContextBuilder` (omit irrelevant sections).
3. **Prompt addenda** per intent in `CoachSystemPrompt`.
4. **Think harder v1:** research @Docs / TN3193; optional two-step plan→answer **sequential** (never parallel `respond`). Log `intent=`, `promptChars=`.

## Key files

- `Signal/Data/Coach/CoachQueryRouter.swift` (new)
- `Signal/Data/Coach/CoachQueryIntent.swift`
- `Signal/Data/Coach/CoachContextBuilder.swift`
- `Signal/Data/Coach/CoachContext.swift`
- `Signal/Data/Coach/CoachSystemPrompt.swift`
- `Signal/Data/Coach/FoundationModelsCoach.swift`
- `SignalTests/CoachQueryRouterTests.swift`, `CoachContextBuilderTests.swift`

## Gate B

- "What should I train today?" → no unsolicited protein essay.
- "Am I hitting protein?" → no ACWR lecture.
- Answers cite real context numbers.

## Out of scope

Cloud Gemini, fine-tuning, markdown UI (A5).

---

# Stream A5 — Chat markdown rendering

## Task

Render coach `###`, lists, **bold**, paragraphs correctly; handle streaming safely.

## Current state

- `CoachMessageFormatting.attributedMarkdown` → `AttributedString(markdown:)`.
- `ChatAssistantBubble` single `Text`; partial stream may break markdown.

## Goals

1. Completed messages: headings, lists, bold, paragraph spacing (native `AttributedString` or approved dep).
2. Streaming: plain or safe subset until complete, then full markdown render.
3. Dark mode on `Surface`.
4. `CoachMessageFormattingTests` with realistic coach outputs.

## Key files

- `Signal/Features/Coach/CoachMessageFormatting.swift`
- `Signal/Features/Coach/ChatView.swift` (bubbles)
- `SignalTests/CoachMessageFormattingTests.swift` (new)

## Gate B

Coach response with `###` and bullets renders readably on device (no raw `###`).

## Out of scope

Router (A4).

---

## Post-merge integration checklist (owner)

- [ ] A1: gym session 30 min, no blank screen
- [ ] A2+A3: paste full Gemini sample, match + rests
- [ ] A4+A5: coach workout Q + formatted markdown reply
- [ ] `./scripts/build-and-test.sh` pass
- [ ] `./scripts/install-watch-app.sh` if Train/watch touched
- [ ] Update this doc: all rows `DONE`, integration checked

---

# Stream A6 — History shows RPE

**Full spec:** `HANDOFF-TRAIN-HISTORY-RPE.md`

Quick summary: `WorkoutHistoryDetailView` shows weight × reps and HR but **omits `SetEntry.rpe`** even though Hevy import and live logging persist it. Add RPE to set rows (working sets); optional session summary mean RPE.

---

# Stream A7 — Exercise homepage (Hevy-style)

**Full spec:** `HANDOFF-EXERCISE-HOMEPAGE.md`

Quick summary: Tappable exercise name → `NavigationStack` push to **Exercise detail** with History, Progress (e1RM chart, volume), How-to (preset copy for exercises in user's Hevy export only). Reuse `ExerciseProgressStore`, `DashboardSparklineChart` patterns, `free-exercise-db.json` instructions via catalog match.

---

## Follow-up (not in this parallel batch)

- **Train M2:** Routine templates with prescribed sets.
- **V3 M7:** Exertion + ACWR deload if not already on `main`.
- **Exercise homepage v2:** Images from free-exercise-db, all catalog exercises, tap from Coach links.
