# Handoff A7 — Exercise homepage (Hevy-style)

**Coordination:** Claim stream **A7** in `PARALLEL-AGENT-PLAN-2026-06-05.md` before starting. Prefer **A6 merged first** if both touch history row strings.

## Problem

User wants to **tap an exercise name** anywhere in Train and open a small **exercise homepage**: history, progress charts (PRs, volume), and how-to. Hevy does this well with proper back navigation. Signal has `ExerciseProgress` (e1RM per session) and catalog metadata but **no exercise detail UI**.

**Scope v1:** Preset how-to content only for exercises that appear in the **owner's Hevy export** (not all 800+ free-exercise-db entries).

## Roadmap check

V2 M2 mentions inline e1RM in the logger, not a dedicated screen. **Not deferred** — build now unless owner says otherwise.

---

## UX (v1)

### Entry points (tappable title → push detail)

1. `WorkoutHistoryDetailView` — section header / exercise name
2. `WorkoutExerciseSectionView` — exercise header in active workout (push, back returns to session)
3. `TrainHomeView` → Recent session → history (via 1)

Use `NavigationStack` + new `TrainRoute.exerciseDetail(ExerciseDetailRoute)` so back stack is correct (do not replace active workout).

### `ExerciseDetailView` layout

**Header:** `ExerciseIllustrationView` + canonical name + `MuscleChipRow`

**Segmented control or tabs:**

| Tab | Content |
|-----|---------|
| **History** | Last N sessions (default 10) with date, sets summary (weight × reps @ RPE), link to full `WorkoutHistoryDetailView` for that session |
| **Progress** | e1RM line chart over time (`ExerciseProgressStore.fetchHistory`); stat cards: **PR e1RM**, **PR weight×reps**, **avg working-set volume** (last 8 sessions) |
| **How-to** | Numbered steps if preset exists; else "No guide for this exercise yet" |

### How-to data (Hevy subset only)

1. **Script or one-time build step:** `scripts/extract-hevy-exercise-titles.sh` (or Swift test helper) reads `fixtures/HevyExport.csv` → distinct `exercise_title` list.
2. **Bundle:** `Resources/HevyExerciseGuides.json` mapping `canonicalName` or normalized title → `{ instructions: [String], sourceExerciseId?: String }`.
3. **Population:** Match each Hevy title to `ExerciseCatalog` via `ExerciseCatalogMatcher`; pull instructions from `free-exercise-db.json` where names align (fuzzy match top 1); manual curator pass for unmatched staples in owner export.
4. **Runtime:** `ExerciseGuideLoader.guide(for catalogEntry:)` returns instructions or nil. **No network.**

Owner does not need all exercises — only those in their export (~dozens, not hundreds).

### Progress metrics

Reuse / extend:

- `ExerciseProgress` — e1RM series (already recorded on finish via `ExerciseProgressStore`)
- **Volume per session:** query `WorkoutExercise` + `SetEntry` for matching `catalogEntry` or normalized title; sum `weightKg * reps` for non-warmup sets per session date
- **PRs:** max e1RM from progress; best single set by estimated 1RM or weight at rep count

Charts: reuse `DashboardSparklineChart` or extract shared `MetricSparklineChart` (avoid duplicate chart logic).

---

## Navigation model

```swift
enum TrainRoute: Hashable {
    case activeWorkout(PersistentIdentifier)
    case history(PersistentIdentifier)
    case editRoutine(PersistentIdentifier?)
    case exerciseDetail(ExerciseDetailRoute) // NEW
}

struct ExerciseDetailRoute: Hashable {
    var catalogID: PersistentIdentifier?  // preferred
    var exerciseTitle: String             // fallback when unmatched
}
```

`TrainHomeView.routeDestination` → `ExerciseDetailView(route:)`

Active workout: wrap section header `Button` → `path.append(.exerciseDetail(...))` without dismissing session.

---

## Key files

| Area | Files |
|------|--------|
| Navigation | `LiveWorkoutCoordinator.swift` (`TrainRoute`), `TrainHomeView.swift` |
| Detail UI | `ExerciseDetailView.swift`, `ExerciseDetailViewModel.swift` (new) |
| Data | `ExerciseDetailHistoryLoader.swift`, `ExerciseGuideLoader.swift`, `HevyExerciseGuides.json` (new) |
| Progress | `ExerciseProgressStore.swift`, optional `ExerciseVolumeCalculator.swift` |
| Entry taps | `WorkoutHistoryDetailView.swift`, `WorkoutExerciseSectionView.swift` |
| Assets | `scripts/build-hevy-exercise-guides.sh` (optional) |
| Tests | `ExerciseDetailHistoryLoaderTests.swift`, `ExerciseGuideLoaderTests.swift` |

## Gate A

- `build_sim` + tests for guide loader + volume aggregation on fixture sessions
- Navigation compiles with new `TrainRoute` case

## Gate B (device)

1. History → tap "Bench Press (Barbell)" (or any logged lift) → detail opens → back returns to history.
2. Active workout → tap exercise name → detail → back returns to active session (not Train home).
3. Progress tab shows e1RM chart if `ExerciseProgress` rows exist.
4. How-to tab shows steps for at least one exercise known to be in Hevy export (e.g. lat pulldown, bench).
5. Exercise with no guide: How-to shows empty state, no crash.

## Out of scope v1

- Images from free-exercise-db `images/` paths
- How-to for entire catalog
- Editing exercise from detail
- Coach deep links (v2)
- watchOS

## Constraints

- iOS 26+, `@Observable` view model, Swift 6
- Privacy: bundled JSON only, no network
- Xcode project: `.cursor/rules/xcode-project-setup.mdc`. Prefer folder sync; bundle `HevyExerciseGuides.json` in target if build requires it.

## On complete

- Status A7 → `DONE` in `PARALLEL-AGENT-PLAN-2026-06-05.md`
- Append to `AGENT-BUILD-UPDATES.md` with list of exercises that received how-to presets
- `MILESTONE COMPLETE: A7 exercise homepage, READY TO COMMIT`

## Follow-up v2

- Tap from Coach / Insights
- Full catalog how-to via on-demand bundle
- Exercise images
- Compare Hevy export list regeneration when user re-imports CSV
