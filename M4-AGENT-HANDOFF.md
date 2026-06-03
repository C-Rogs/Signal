# M4 agent handoff (Profile + goals)

Last updated after commit on `main` that adds warmup suggestions + cue/RPE fixes. Use this to start or resume **M4** without re-discovering local WIP.

## Product goal (from spec)

**M4. Profile + goals** (`build-a-very-detailed-foamy-pixel.md`):

- `UserProfile` + goal model (effective-dated profile facts per spec; current WIP uses a simpler `TrainingGoal` row).
- Lightweight onboarding: sex/height/bodyweight target, equipment, availability, experience, injuries, active goal(s).
- **All coaching conditioned on profile/goals** (cue RIR targets, warmup prescription goal, future prescription).

## Already shipped on `main` (do not redo)

| Area | Status |
|------|--------|
| M3.5 set timestamps | `SetEntry.startedAt` / `completedAt`, `LiveWorkoutStore` chains next set |
| M3.5 cue engine | `CueEngine.swift`, `SetCueEvaluator`, `SetCueBannerView`, tier tests |
| Warmup suggestions | `WarmupRecommendationEngine`, `TrainPreferences` toggle in Settings, banner in `WorkoutExerciseSectionView` |
| RPE logging UX | No RPE autofill on new sets; **logging RPE via sheet auto-completes the set** (`SetRowView.markCompleteIfNeeded`) |
| `GoalType` enum | Committed (`hypertrophy`, `strength`, `powerlifting`, `generalFitness`) with `defaultRIR` |

### Integration points waiting on M4

1. **`CueEngine` / `SetCueEvaluator`**  
   - `ExerciseCueInput` has `targetRIR` (default `CueEngine.fallbackTargetRIR = 2`).  
   - Wire `ProfileGoalRepository.targetRIR(in:)` in `SetCueEvaluator` when M4 lands (local WIP had this; reverted on main to avoid orphan dependency).

2. **`WorkoutExerciseSectionView.trainingGoal`**  
   - Hardcoded `.hypertrophy` for `WarmupRecommendationInput`.  
   - Replace with `fetchTrainingGoal` → `primaryGoal`.

3. **Settings**  
   - Train section has warmup toggle only.  
   - Optional: restore "Profile and goals" `NavigationLink` to `ProfileGoalsView` once M4 ships.

## Local WIP (exists on disk, **not** on `main`)

Add these to the **Signal** target in Xcode (human owns `.pbxproj`):

| File | Role |
|------|------|
| `Data/Models/UserProfile.swift` | SwiftData profile (height, DOB, sex, bodyweight snapshot) |
| `Data/Models/TrainingGoal.swift` | Primary goal, weekly days, `targetRIR`, notes |
| `Data/Models/BodyweightEntry.swift` | Bodyweight history |
| `Data/Profile/ProfileGoalRepository.swift` | fetch/create, `targetRIR`, bodyweight append |
| `Features/Profile/ProfileGoalsView.swift` | Edit form |
| `Features/Profile/ProfileGoalsViewModel.swift` | `@Observable` VM |
| `SignalTests/ProfileTests.swift` | Repository tests |

**Also revert-then-needed edits (were local, reverted for scoped commits):**

- `App/ModelContainer+Signal.swift`: add `UserProfile`, `BodyweightEntry`, `TrainingGoal` to `Schema([...])`.
- `Features/Profile/ProfileView.swift`: `ProfileDestination.profileGoals` → `ProfileGoalsView()`.

**Untracked / out of scope for M4 core:** `Core/Notifications/` (do not pull in unless milestone says so).

## Suggested M4 task order

1. Commit schema + models + repository + tests (with `ModelContainer` update).
2. Ship `ProfileGoalsView` entry from Profile tab (not required in Settings if Profile tab is canonical).
3. Wire `SetCueEvaluator` + warmup `trainingGoal` to repository.
4. Minimal onboarding sheet (skippable) if spec requires first-run; else Profile-only edit is enough for V2 slice.
5. Run `./scripts/build-and-test.sh`; device smoke on `H3XLDTHR74` for profile save + live workout cue/warmup after goal change.

## Constraints (repo rules)

- iOS 26+, Swift 6, `@Observable`, no new SPM deps without approval.
- **Do not edit** `.pbxproj`, entitlements, storyboards.
- Privacy: no runtime network.
- Build: XcodeBuildMCP `build_sim` id `20DDD35B`; tests id `311A9753`; device `H3XLDTHR74`.
- Git: push as **C-Rogs** only; no Cursor commit trailers.

## Acceptance hints

- Changing primary goal updates `TrainingGoal.targetRIR` and changes cue/warmup behavior without app restart.
- Profile fields persist across relaunch (SwiftData).
- Existing workouts/cues unchanged for users with no goal row (fallback RIR 2, hypertrophy warmups until goal set).

## Recent commits (context)

- `2a5bb70` M3.5 cues + timestamps + dashboard layout
- `446588a` Warmup suggestions + cue/RPE autofill fixes (+ `GoalType`)
- (next) RPE sheet auto-completes set + this handoff doc
