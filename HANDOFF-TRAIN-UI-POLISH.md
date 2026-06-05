# Train UI polish handoff

## Shared components (new)

| File | Purpose |
|------|---------|
| `TrainChrome.swift` | `screenBackground`, `horizontalPadding`, `trainSurfaceCard()` modifier |
| `TrainSectionHeader.swift` | `.headline` title + subtle divider |
| `TrainStatCard.swift` | Surface stat card for progress metrics |
| `TrainStatusChip.swift` | Warning / positive / secondary / destructive chips |

## Per screen

### TrainHomeView
- Replaced `List` with `ScrollView` + card layout
- Primary filled **Start Workout**; bordered **Import Workout**
- Deload and busy day use `TrainStatusChip`; deload detail on Surface card
- Routines and Recent use `TrainSectionHeader` + Surface rows
- Empty routines: `ContentUnavailableView` with **New routine** CTA
- Empty recent: friendly empty state

### ActiveWorkoutView + WorkoutExerciseSectionView + SetRowView
- Summary bar on Surface card; chips via `TrainStatusChip`
- Exercise blocks wrapped in Surface card; header tint simplified
- Set numbers use `.body.monospacedDigit()`; complete/RPE 44pt targets
- VoiceOver on complete toggle; all test `accessibilityIdentifier`s preserved
- **P0 preserved:** no keyboard dismiss on `.inactive`, no ScrollView `.id`, `VStack` not `LazyVStack`

### GeminiWorkoutImportView + Preview
- Import: Surface text editor, inline parse error card, bottom **Preview Workout** CTA
- Preview: ScrollView + exercise Surface cards; match badges via `TrainStatusChip`
- Prominent bottom **Start Workout**; VoiceOver on import rows

### ExerciseDetailView
- Header and tabs on consistent Surface cards
- Progress uses `TrainStatCard` + `TrainSectionHeader`
- History set lines use monospaced digits; empty how-to/history unchanged copy

### WorkoutHistoryDetailView
- ScrollView + per-exercise Surface cards
- Session summary card with emphasized avg RPE
- Set rows: muted set label, prominent load line, HR as caption

### Sheets
- **LogSetRPEView:** set summary above RPE, true black/OLED background
- **ExercisePickerView:** hidden list background, Surface filter bar, typography tokens
- **WorkoutSwapSheet:** ScrollView + Surface cards, primary **Suggest Swap** / **Apply Swap**

## Before / after (owner notes)

1. **Train home:** Start and Import are the first two full-width buttons; less list chrome.
2. **Active workout:** Each exercise is one Surface card; weight/reps read larger.
3. **Import preview:** Matched/Unmatched chips are color-coded capsules on each card.
4. **History:** Load and RPE right-aligned in semibold; easier scan than plain `List`.
5. **Exercise detail:** Progress stats share the same card style as Dashboard.
6. **RPE sheet:** Shows which set you are logging above the big number.
7. **Deload/busy/recovery chips:** Same component everywhere (home, live summary).
8. **OLED dark:** `TrainChrome.screenBackground` is `.black` on all Train screens.
9. **Swap sheet:** Matches import chrome instead of plain `Form`.
10. **Rest bar:** Skip/+15/-15 controls meet 44pt minimum width.

## Human Xcode

Add to **Signal** target (if not already synced):

- `Features/Train/TrainChrome.swift`
- `Features/Train/TrainSectionHeader.swift`
- `Features/Train/TrainStatCard.swift`
- `Features/Train/TrainStatusChip.swift`
