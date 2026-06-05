# V3 M6 handoff: Personal recovery baseline + disruptors

## What shipped

- **RecoveryDisruptorEpisode** SwiftData model with kinds: alcohol, trainingLoad, sleepDebt, illnessLike, unknown.
- **PersonalReadinessCalculator** builds personal P25/median/P75 from up to 60 scored days; calibrated at ≥21 days.
- **RecoveryDisruptorEngine** user tag ("Drank last night"), undo, nightly proxy inference (alcohol-first).
- **Train** uses personal bands when calibrated; fallback 70/40 when not.
- **Dashboard** shows your norm, delta vs norm, disruptor tag button, personal status bands.
- **Watch payload** optional `personalP25`, `personalP75`, `isCalibrated` (backward compatible decode).
- **Coach + Briefing** include personal readiness and disruptor context.
- **Reflection** new insights: `recoveryDisruptorActive`, `personalReadinessLow` with dedupe vs sleep/strain rules.

## Architecture

```
DailyMetric → RecoveryScoreCalculator (unchanged formula)
           → PersonalReadinessCalculator (percentiles + debt)
RecoveryDisruptorEpisode → RecoveryDisruptorEngine (tag + infer)
                         → Train / Dashboard / Watch / Coach / Reflection
```

Alcohol proxy (confidence 0.6): prior night sleep < 6.5h AND RHR delta > 3 AND suppressed HRV. Training load (ACWR > 1.5) wins when both fire. UI never says "you drank" below confidence 0.75.

## Human Xcode (required before first run)

1. Add to **Signal** iOS target:
   - `Data/Models/RecoveryDisruptorEpisode.swift`
   - `Data/Recovery/RecoveryDisruptorHeuristics.swift`
   - `Data/Recovery/PersonalReadinessCalculator.swift`
   - `Data/Recovery/RecoveryDisruptorEngine.swift`
   - `Features/Dashboard/RecoveryDisruptorTagButton.swift`
2. Add to **SignalTests**:
   - `PersonalReadinessCalculatorTests.swift`
   - `RecoveryDisruptorEngineTests.swift`
3. Confirm `RecoveryDisruptorEpisode.self` is in `ModelContainer+Signal.swift` schema (agent added; verify lightweight migration on device if store already exists).

## Gate B checklist (device)

| ID | Test | Pass |
|----|------|------|
| **R1** | Personal norm | After ≥3 weeks data, Dashboard shows "Your norm" and delta; score ~52 on ~50 median day does NOT show low-recovery chip |
| **R2** | Alcohol tag | Tap "Drank last night"; next day chip/nudge reflects recovery debt; Train suggests hold (not add) |
| **R3** | Tag learning | After 3+ tags over weeks, alcohol recovery uses learned duration (check logs: `personal readiness`) |
| **R4** | Proxy disruptor | Untagged bad night (short sleep + high RHR): generic disrupted message, not "you drank" unless high confidence |
| **R5** | Train calibrated | Easy set on above-P75 day → add load nudge possible; below-P25 → hold |
| **R6** | Regression | V4 M1–M3 Train gates still pass; watch recovery sync OK |

Console filters: `category:recovery`, `category:workout`.

### R2 steps

1. Open Dashboard recovery card.
2. Tap **Drank last night** (or **Undo** same day).
3. Start Train next morning; confirm chip **Recovering from last night** or **Recovery below your norm**.
4. Complete easy set; confirm hold nudge, not add.

### R5 steps

1. Wait until calibrated (≥21 scored days in history).
2. On an above-your-P75 day, complete easy set at target RIR → add nudge.
3. On a below-your-P25 day → hold nudge and low chip.

## Out of scope (follow-up)

- Athlytic exertion score, ACWR deload automation, Coach LLM disruptor RAG, complication layout changes.
