# M4 architecture handoff (Profile + goals)

Last updated: after profile Health sync, UI polish, and `2e8df88` baseline on `main`.

## Product scope (V2 M4)

Shipped slice (not full foamy-pixel M4):

- SwiftData: `UserProfile`, `BodyweightEntry` (append-only), `TrainingGoal` (singleton `primary`).
- Profile UI: about you + training goal, explicit save, Health auto-fill.
- Coaching hooks: `ProfileGoalRepository.targetRIR` / `primaryGoal` wired into cues (RIR on `ExerciseCueInput`) and warmup engine.
- **Out of scope for this slice:** effective-dated profile history, equipment, injuries, first-run onboarding sheet, JSON export.

## Data model

| Model | Key | Notes |
|-------|-----|--------|
| `UserProfile` | `profileKey == "me"` | `heightCm`, `bodyweightKg` (latest snapshot), `dateOfBirth`, `biologicalSex` (`male` / `female` / `other` / nil) |
| `BodyweightEntry` | — | Append-only log `{ date, kg }`; never update rows in app code |
| `TrainingGoal` | `goalKey == "primary"` | `primaryGoal` (`GoalType`), `weeklyTrainingDays` 1–7, `targetRIR` 0–5, `notes`, `updatedAt` |

`GoalType.defaultRIR`: hypertrophy 2, strength 1, powerlifting 0, generalFitness 2.

## Apple Health integration

**Yes, HealthKit exposes date of birth and biological sex** as characteristics (not quantity samples):

- `HKHealthStore.dateOfBirthComponents()` → `Date`
- `HKHealthStore.biologicalSex()` → mapped to profile sex storage

These types are included in `HealthKitTier1Kind.authorizationReadTypes` (alongside existing Tier 1 reads). Users who already granted Health access may need to open Import and sync again for iOS to expose characteristics.

**Body weight**

- Live: latest `HKQuantityType.bodyMass` sample (sorted by `endDate`).
- Fallback: most recent `DailyMetric.bodyMassKg` from local Health sync/import (up to 120 days lookback).
- **Recency:** only applied if measured within **30 days** (`ProfileHealthKitReader.recentBodyMassMaxAge`).
- **Merge rule:** append `BodyweightEntry` when Health sample is newer than latest entry or profile has no weight; do not overwrite existing DOB/sex.

Flow on `ProfileGoalsView` appear:

1. `ProfileGoalsViewModel.load()` → `HealthKitManager.fetchProfileHealthSnapshot`.
2. `ProfileGoalRepository.applyHealthSnapshot` → optional banner ("Updated body weight from Apple Health", etc.).
3. Form fields populated from SwiftData.

## Repository API (`ProfileGoalRepository`)

- `fetchProfile` / `fetchTrainingGoal`: read-only; return `nil` on fresh install (no crash).
- `fetchOrCreateProfile` / `fetchOrCreateTrainingGoal`: fetch by `profileKey` / `goalKey`, insert only when missing; idempotent; collapses duplicate rows if ever present.
- Coaching reads use **fetch only** + defaults (`hypertrophy`, RIR 2), not create.
- Profile screen **load** does not create rows; **save** (or Health apply with data) calls fetch-or-create.
- `primaryGoal(in:)` → `.hypertrophy` if no row.
- `targetRIR(in:)` → `2` if no row.
- `appendBodyweight(kg:date:save:)`
- `applyHealthSnapshot(_:to:in:)`

## UI

- **Entry:** Profile tab → Profile and goals; Settings → Profile and goals.
- **Save:** pinned bottom bar, title `Save profile and goal`; states idle / saving / saved / failed with banners.
- **Notifications:** `Notification.Name.goalDidChange` on save; `WorkoutExerciseSectionView` listens to refresh warmup suggestions.

## Coaching integration

| Consumer | Source | Fallback |
|----------|--------|----------|
| `SetCueEvaluator` | `targetRIR(in:)` on `ExerciseCueInput` | RIR 2 |
| `WorkoutExerciseSectionView` | `primaryGoal(in:)` for `WarmupRecommendationInput` | hypertrophy |
| `CueEngine` tiers | unchanged | `targetRIR` stored for future prescription, not used in tier rules yet |

## File map

```
Signal/Data/Models/UserProfile.swift
Signal/Data/Models/BodyweightEntry.swift
Signal/Data/Models/TrainingGoal.swift
Signal/Data/Models/GoalType.swift
Signal/Data/Profile/ProfileGoalRepository.swift
Signal/Data/Profile/ProfileHealthKitReader.swift
Signal/Core/Notifications/SignalNotifications.swift
Signal/Features/Profile/ProfileGoalsView.swift
Signal/Features/Profile/ProfileGoalsViewModel.swift
SignalTests/ProfileTests.swift
```

Touches: `ModelContainer+Signal.swift`, `CueEngine.swift` (`SetCueEvaluator`), `WorkoutExerciseSectionView.swift`, `HealthKitManager.swift`, `HealthKitTier1Types.swift`, `ProfileView.swift`, `SettingsView.swift`.

## Verification

```bash
./scripts/build-and-test.sh
```

Device smoke (`H3XLDTHR74`): Profile → allow Health → confirm weight/DOB fill when recent; save Strength → RIR 1; live workout warmup style changes.

## Follow-ups (not M4)

- Effective-dated `UserProfile` facts per long spec.
- Onboarding sheet (skippable).
- Use `targetRIR` in cue tier classification.
- Local JSON export of profile/goal models.
- Re-prompt Health if characteristics denied while quantity access granted.

## Git

- Commits: human only, **C-Rogs**, no Cursor trailers.
- Push: `GH_TOKEN=$(gh auth token -u C-Rogs) git push origin main`
