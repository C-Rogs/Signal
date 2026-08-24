# Handoff A6 — Workout history shows RPE

**Coordination:** Claim stream **A6** in `PARALLEL-AGENT-PLAN-2026-06-05.md` before starting.

## Problem

User expects RPE in completed workout history. Data exists on `SetEntry.rpe` (Hevy CSV import + live logging) but **`WorkoutHistoryDetailView` does not display it**.

Current strength row (line ~103):

```swift
Text("\(formatter.formatMassKg(set.weightKg)) × \(set.reps.map(String.init) ?? "—")")
```

HR attribution is shown; RPE is not.

## Goal

Show RPE on history set rows for working sets when `set.rpe != nil`. Match live logging style (`WorkoutRPEScale.compactLabel`).

### UI spec

- Strength: `Set N` … `72.5 kg × 10 · RPE 8` (or `@ RPE 8` — pick one, use `WorkoutRPEScale` consistently).
- Warmups: omit RPE or show if present (prefer omit for warmup).
- Cardio: unchanged unless RPE logged.
- Optional session footer: mean working-set RPE for the workout (one line under title).

### Non-goals

- Editing history RPE inline
- Exercise homepage (A7)
- New models

## Key files

- `Signal/Features/Train/WorkoutHistoryDetailView.swift` (primary)
- `Signal/Data/Workout/WorkoutRPEScale.swift` (label helper)
- `SignalTests/` — add `WorkoutHistoryDetailFormattingTests` or extend existing if any

## Gate A

- Unit test: formatting helper returns expected string for set with rpe 8.5, nil rpe, warmup.

## Gate B (device)

1. Open Train → Recent → session imported from Hevy or finished live with RPE logged.
2. Each working set shows RPE where data exists.
3. Sets without RPE unchanged (no stray "RPE —").

## Constraints

- iOS 26+, SwiftUI, `DisplayUnitFormatter` for mass
- Minimal diff. Xcode project edits only if build requires (`.cursor/rules/xcode-project-setup.mdc`).

## On complete

- Status A6 → `DONE` in `PARALLEL-AGENT-PLAN-2026-06-05.md`
- Append to `AGENT-BUILD-UPDATES.md`
- `MILESTONE COMPLETE: A6 history RPE, READY TO COMMIT`
