# Train M2 — Routine templates with prescribed sets

## Task

Upgrade **Routines** from exercise-only lists to **full workout templates** (prescribed sets, rest, warmup flags) and wire **Save as Routine** from Gemini import preview.

**Prerequisites shipped:** Gemini paste import with `ParsedPlanStartRequest` + `presetSets` on `LiveWorkoutStore.addExercise`, Train UI polish (`TrainChrome`), P1 perf pass, Train M3 haptics.

---

## Problem

Today `Routine` / `RoutineExercise` store only catalog + title. `LiveWorkoutStore.start(from: Routine)` adds empty exercises and autofills from last session. Gemini import already starts workouts with full prescriptions but cannot save them as reusable routines.

Owner workflow: plan in Gemini → paste → **Save as Routine** → start from routine on gym days without re-pasting.

---

## Goal

1. SwiftData models persist prescribed sets per routine exercise (weight/reps/RPE/rest/warmup/note).
2. `start(from: Routine)` prefills sets like `start(fromParsedPlan:)` (no last-session autofill when presets exist).
3. **Routine editor** can add/edit/remove sets per exercise (minimum viable, not a full duplicate of active workout UI).
4. **Gemini import preview** adds **Save as Routine** (secondary CTA); does not start workout.
5. Existing name-only routines keep working (empty presets → current autofill behavior).

---

## Out of scope

- Save finished workout → routine (v2)
- Routine folders / scheduling / Coach "start routine X"
- Cardio distance/duration presets unless parser already provides them (support fields if easy)
- `.pbxproj` edits
- Watch changes
- Changing P0 Train stability (`TrainScenePhaseKeyboardPolicy`, `isViewingActiveWorkout`, accessory freeze)

---

## Data model

Extend under `Signal/Data/Catalog/` (or `Data/Workout/` if you prefer colocation).

### `RoutineExercise` (extend)

Add:

- `restDurationSeconds: Int` (default 90)
- `autoStartRestOnSetComplete: Bool` (default true, match `WorkoutExercise`)
- `@Relationship(deleteRule: .cascade, inverse: \RoutinePresetSet.routineExercise) var presetSets: [RoutinePresetSet]`

### New `RoutinePresetSet` @Model

Mirror `SetAutofillTemplate` / `SetEntry` prescription fields:

| Field | Type |
|-------|------|
| `setIndex` | Int |
| `setType` | String (`WorkoutSetType` storage) |
| `weightKg` | Double? |
| `reps` | Int? |
| `distanceKm` | Double? |
| `durationSeconds` | Int? |
| `rpe` | Double? |
| `prescriptionNote` | String? |
| `restDurationSeconds` | Int? |
| `routineExercise` | RoutineExercise? |

Add helpers:

```swift
extension RoutinePresetSet {
    func asAutofillTemplate() -> SetAutofillTemplate { ... }
}
```

### Migration / backward compatibility

- Existing `RoutineExercise` rows: `presetSets` empty → `start(from:)` unchanged (last-session autofill).
- No destructive migration; SwiftData lightweight migration should suffice for new optional fields with defaults.

---

## Store layer

New `RoutineTemplateStore` (or methods on `LiveWorkoutStore`) in `Data/Workout/`:

| API | Behavior |
|-----|----------|
| `createRoutine(name:from: ParsedPlanStartRequest)` | Insert `Routine` + exercises + preset sets from parsed plan |
| `updateRoutine(_:from:)` | Replace exercises/sets (simple: delete children, reinsert) |
| `presetTemplates(for: RoutineExercise)` | `[SetAutofillTemplate]` sorted by `setIndex` |

### Update `start(from: Routine)`

```swift
for (index, slot) in slots.enumerated() {
    let templates = slot.presetSets.isEmpty
        ? nil
        : slot.presetSets.sorted(by: \.setIndex).map { $0.asAutofillTemplate() }
    _ = try addExercise(
        to: session,
        catalogEntry: slot.catalogEntry,
        exerciseTitle: title,
        order: index,
        presetSets: templates,
        restDurationSeconds: slot.presetSets.isEmpty ? nil : slot.restDurationSeconds
    )
}
```

Log `category:workout` on create/start.

---

## UI

### `RoutineEditorView` (upgrade)

Replace exercise-only list with expandable exercise rows:

- Name field (unchanged)
- Per exercise: title, rest seconds stepper or field, toggle auto-rest
- **Sets:** compact rows (set #, W/N, weight, reps); Add set / delete set
- Reuse `DisplayUnitFormatter`, `WorkoutSetType`, `TrainChrome` / `trainSurfaceCard`
- Keep reorder + delete exercises
- 44pt targets; OLED black background

MVP acceptable: tap exercise → push `RoutineExerciseEditorView` sheet with set list instead of inline everything.

### `GeminiWorkoutImportPreviewView`

Below **Start Workout**, add bordered **Save as Routine**:

1. Prompt for routine name (default `workoutTitle`)
2. Build `ParsedPlanStartRequest` from current preview state (same as `startWorkout()`)
3. `RoutineTemplateStore.createRoutine(...)`
4. `TrainFeedback` selection haptic if M3 shipped
5. Dismiss import flow or show brief confirmation; do not start workout

### `TrainHomeView`

Routine row subtitle: show set count when presets exist, e.g. `4 exercises · 16 sets`. Name-only routines: `4 exercises` only.

---

## Tests (`SignalTests`)

1. `createRoutine(from:)` persists exercises + preset sets
2. `start(from: routineWithPresets)` creates session sets matching templates (no autofill from history)
3. `start(from: routineWithoutPresets)` still uses `LastSessionAutofill` behavior
4. Rest duration on exercise + per-set rest preserved

Pure mapping tests OK; in-memory `SignalModelContainer`.

---

## Build and verify (device-first)

Per `.cursorrules`:

1. **Default:** `build_device` → `install_app` → `launch_app` on iPhone `00008140-001E34E10A01801C`
2. **Do not run sim** unless compile-fix is faster or unit tests required (`test_sim` only for test milestone coverage)
3. **Agent-owned:** grep/read `.pbxproj` for new file names; fix compile errors before escalating
4. **Human Xcode section:** leave empty if `build_device` passes

### Gate A (agent — required)

- `build_device` + install + launch **pass**
- Unit tests for routine template store **pass** (sim OK for tests only)
- Agent verifies on device:
  - Import sample → Preview → **Save as Routine**
  - Train home → tap routine → workout starts with prescribed sets visible
  - Edit routine → add set → start again reflects change

### Gate B (human — only if blocked)

- Device offline / signing failure
- Subjective UX feel
- Empty if Gate A device script passed

---

## P0 regression (agent checks on device)

After starting routine workout:

1. App switcher out/in: workout UI not blank
2. Keyboard on set field → switcher → return: field still usable
3. Rest timer + haptics still work if M3 shipped

---

## Docs

- Append `AGENT-BUILD-UPDATES.md` (device build result, files touched)
- Output: `MILESTONE COMPLETE: Train M2 routine templates, READY TO COMMIT`

---

## Files likely touched

| Area | Files |
|------|--------|
| Models | `Routine.swift` (+ `RoutinePresetSet.swift` new) |
| Store | `RoutineTemplateStore.swift` (new), `LiveWorkoutStore.swift` |
| Editor | `RoutineEditorView.swift`, optional `RoutineExerciseEditorView.swift` |
| Import | `GeminiWorkoutImportPreviewView.swift` |
| Home | `TrainHomeView.swift` |
| Tests | `RoutineTemplateStoreTests.swift` (new) |

---

## Sample Gemini paste (manual test)

```
Push Day
Bench Press 3x8 @ 80kg rest 90s
Incline DB Press 3x10 @ 28kg
Cable Fly 3x12 rest 60s
```

Expect: save routine → start → 3 exercises, sets prefilled, rest on complete.
