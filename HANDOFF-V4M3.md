# Signal — V4 M3 — In-session load autoregulation (readiness + RPE)

## Scope

- **In scope:** Rule-based load prescription nudges after set complete; session low-recovery chip; composed set banner (tier + HR + load); unit tests; device gate D9–D12.
- **Out of scope:** Google Calendar; Athlytic exertion score; auto-mutating logged weight; simulator fake HR.

## Policy (`LiveLoadAutoregulation.swift`)

| Constant | Value |
|----------|-------|
| Recovery high | score ≥ 70 |
| Recovery low | score < 40 |
| Recovery moderate | 40 ≤ score < 70 |
| Easy RPE max | ≤ 6 (CueEngine aligned) |
| Grind RPE min | ≥ 9 (CueEngine `isHighRPE`) |
| Suggested increment | 2.5 kg |

### Load nudge rules (first match)

1. RPE ≥ 9: `RPE 9+. Stay at this weight for remaining sets.`
2. Recovery low: `Recovery low. Hold weight.` (no add on easy sets)
3. Recovery high + easy at target RIR (+ reps ≥ target when known): `Easy set at target RIR. Add 2.5 kg next set.`
4. Otherwise: no load line

Target RIR check: `effectiveRIR = max(0, 10 - rpe)` must be ≥ `targetRIR` from profile.

## Composed set cue (`LiveSetCueComposer` in `LiveWorkoutAutoregulation.swift`)

Max 3 lines, display order:

1. Tier cue (CueEngine performance)
2. Live HR rest nudge (V4 M2)
3. Load / readiness nudge (V4 M3)

## UI

- `WorkoutExerciseSectionView`: builds load nudge via `LiveLoadCueEvaluator`; composes banner with `LiveSetCueComposer`.
- `ActiveWorkoutView`: loads `RecoveryEngine.todayRecoveryScore`; passes score into sections; summary bar chip when low recovery.
- `WorkoutLiveSummaryBar`: optional `recoveryChipTitle` (accessibility id `lowRecoveryChip`).

## Gate A (agent)

```bash
./scripts/build-and-test.sh
# or MCP test_sim with:
# -only-testing:SignalTests/LiveLoadAutoregulationTests
# -only-testing:SignalTests/LiveWorkoutAutoregulationTests
# -only-testing:SignalTests/CueEngineTests
```

## Gate B (device, paired iPhone + Watch)

Prereq: `./scripts/install-watch-app.sh`. D1–D8 unchanged from V4 M2.

| ID | Test | Pass criteria |
|----|------|---------------|
| **D9** | Low recovery hold | Dashboard recovery < 40; start workout; complete easy set (RPE ≤ 6); load line says hold, no add weight |
| **D10** | High recovery add | Recovery ≥ 70; easy working set at target RPE/RIR; load line suggests +2.5 kg |
| **D11** | Grind hold | RPE ≥ 9 on working set; load line says stay / top set, not add |
| **D12** | Composed cue | Hard set with HR ≥ 150: banner shows tier, then HR line, then load line (when applicable) |

Console: `category:workout`, `category:recovery`.
