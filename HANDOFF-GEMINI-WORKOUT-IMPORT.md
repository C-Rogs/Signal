# Signal — Train M1 — Gemini workout paste import

**For:** Builder agent or human device gate.

**Goal:** Paste Gemini (or similar) workout text into Train, preview catalog matches, start a live session with pre-filled sets.

---

## User flow

1. Train → **Import workout**
2. Paste text (or **Paste** from clipboard) → **Preview**
3. Review title, exercises, match badges, set summaries, coaching notes
4. Fix unmatched exercises via **Change exercise** → `ExercisePickerView`
5. **Start workout** → `ActiveWorkoutView` with prescribed sets (not completed)

---

## Parser format (v1, strength only)

- First line: workout title (unless exercise-first paste; see `GeminiWorkoutPasteParser`)
- Exercise lines: free text; parenthetical subtitles kept for display, stripped for catalog match
- Set lines: `Set N: <weight> kg|lb [DBs] x <reps> [@ <rpe> RPE] [(note|Warm-up)]`
- Blank lines ignored; malformed lines in `skippedLines`

---

## Architecture

| Component | Role |
|-----------|------|
| `GeminiWorkoutPasteParser` | Pure parse → `ParsedWorkoutPlan` |
| `ParsedWorkoutTitle.catalogMatchTitle` | Strip trailing `(subtitle)` for matcher |
| `GeminiWorkoutImportView` | TextEditor + paste + preview sheet |
| `GeminiWorkoutImportPreviewView` | Catalog match UI + start |
| `LiveWorkoutStore.start(fromParsedPlan:)` | Session + exercises + `SetEntry` rows |
| `SetEntry.prescriptionNote` | Coaching text from set parens (no Train UI v1; future Coach) |

`addExercise(presetSets:)` skips `LastSessionAutofill` when preset sets are provided.

---

## Gate A (agent)

- `GeminiWorkoutPasteParserTests` (18 cases)
- `LiveWorkoutStoreTests` including `testStartFromParsedPlanPrefillsSetsWithoutAutofill`
- `build_sim` pinned iPhone 16 Pro sim

---

## Gate B (device)

1. Copy Gemini export → Train → Import → Preview matches sample
2. Start → exercises/sets show correct kg, reps, RPE, warmup in `ActiveWorkoutView`
3. Complete a set → finish → HK write OK
4. Catalog: lat pulldown, chest press, lateral raise match or manual pick works

---

## Out of scope v1

- Save as routine with set templates (`RoutineSetTemplate`)
- Coach context reading `prescriptionNote`
- Share sheet / Shortcuts
- Cardio duration/distance lines
- `SetRowView` caption for notes

---

## Follow-up

- `RoutineSetTemplate` + Save as routine + edit sets in `RoutineEditorView`
- Surface `prescriptionNote` in Coach active-session context and cues
