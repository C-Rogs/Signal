# Signal — V4 M2 — Live HR cues + dynamic rest

## Scope

- **In scope:** Rule-based live HR rest nudge after set complete; automatic rest timer extension when HR stays elevated during an active rest; unit tests; device gate checklist.
- **Out of scope:** Load prescription changes from live readiness/RPE; Google Calendar; simulator fake HR injection.

## Policy (code: `LiveWorkoutAutoregulation.swift`)

| Constant | Value |
|----------|-------|
| Elevated HR threshold | 150 BPM |
| Fresh HR max age | 45 s |
| Rest extension | +30 s |
| Max extensions per rest | 2 |
| Min gap between extensions | 20 s |
| No extension when rest remaining | ≤ 8 s |

## Wiring

- `WorkoutExerciseSectionView`: composes tier cue + HR nudge via `LiveHRCueEvaluator.composedSetCue` using `LiveWorkoutWatchBridge`.
- `ActiveWorkoutView`: each 1 s tick, `DynamicRestTimerEvaluator` may extend the active rest timer and surface notice on `FloatingRestTimerBar`.

## Gate A (agent)

```bash
./scripts/build-and-test.sh
# or MCP test_sim with onlyTesting SignalTests/LiveWorkoutAutoregulationTests
```

## Gate B (device)

See `AGENT-BUILD-UPDATES.md` latest V4 M2 section (numbered tests D1–D8).
