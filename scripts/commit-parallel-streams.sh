#!/usr/bin/env bash
# Sequential commits for parallel streams A1–A7 (merge order). Run from repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

commit() {
  local msg="$1"
  shift
  if [[ $# -eq 0 ]]; then
    echo "skip empty commit: $msg"
    return 0
  fi
  git add "$@"
  if git diff --cached --quiet; then
    echo "skip (nothing staged): $msg"
    return 0
  fi
  git commit -m "$msg"
  echo "committed: $msg"
}

# A1 — blank screen
commit "Fix active workout blank screen by replacing List with ScrollView." \
  Signal/Signal/Features/Train/ActiveWorkoutView.swift \
  Signal/Signal/Features/Train/ActiveWorkoutContainerView.swift \
  Signal/Signal/Features/Train/SetRowView.swift \
  Signal/Signal/Features/Train/TrainKeyboard.swift \
  Signal/Signal/Features/Train/WarmupSuggestionBannerView.swift \
  Signal/SignalTests/TrainScenePhaseKeyboardPolicyTests.swift

# A2 — catalog
commit "Improve exercise catalog matching for Gemini import staple names." \
  Signal/Signal/Data/Catalog/CatalogAliasGenerator.swift \
  Signal/Signal/Data/Catalog/CatalogMatchReport.swift \
  Signal/Signal/Data/Catalog/ExerciseCatalogCurator.swift \
  Signal/Signal/Data/Catalog/ExerciseCatalogMatcher.swift \
  Signal/Signal/Data/Catalog/ExerciseCatalogSeeder.swift \
  Signal/Signal/Data/Catalog/ExerciseTitleNormalizer.swift \
  Signal/SignalTests/ExerciseCatalogTests.swift

# A3 — import rest timers
commit "Parse rest durations and harden Gemini workout paste import." \
  Signal/Signal/Data/Workout/GeminiWorkoutPasteParser.swift \
  Signal/Signal/Data/Workout/ParsedWorkoutPlan.swift \
  Signal/Signal/Data/Workout/LiveWorkoutStore.swift \
  Signal/Signal/Data/Workout/LastSessionAutofill.swift \
  Signal/Signal/Data/Models/SetEntry.swift \
  Signal/Signal/Data/Backup/BackupDTO.swift \
  Signal/Signal/Data/Backup/BackupService.swift \
  Signal/Signal/Features/Train/GeminiWorkoutImportView.swift \
  Signal/Signal/Features/Train/GeminiWorkoutImportPreviewView.swift \
  Signal/SignalTests/GeminiWorkoutPasteParserTests.swift \
  Signal/SignalTests/LiveWorkoutStoreTests.swift \
  HANDOFF-GEMINI-WORKOUT-IMPORT.md

# A4 — coach router
commit "Route coach queries by intent and scope context to each question type." \
  Signal/Signal/Data/Coach/CoachQueryRouter.swift \
  Signal/Signal/Data/Coach/CoachContextBuilder.swift \
  Signal/Signal/Data/Coach/CoachContext.swift \
  Signal/Signal/Data/Coach/CoachQueryIntent.swift \
  Signal/Signal/Data/Coach/CoachSystemPrompt.swift \
  Signal/Signal/Data/Coach/FoundationModelsCoach.swift \
  Signal/SignalTests/CoachQueryRouterTests.swift \
  Signal/SignalTests/CoachContextBuilderTests.swift

# A5 — chat markdown
commit "Render coach chat markdown reliably and show plain text while streaming." \
  Signal/Signal/Features/Coach/CoachMessageFormatting.swift \
  Signal/Signal/Features/Coach/ChatView.swift \
  Signal/SignalTests/CoachMessageFormattingTests.swift

# A6 — history RPE
commit "Show RPE on workout history set rows and session mean RPE." \
  Signal/Signal/Data/Workout/WorkoutHistoryDetailFormatting.swift \
  Signal/SignalTests/WorkoutHistoryDetailFormattingTests.swift \
  HANDOFF-TRAIN-HISTORY-RPE.md

# A7 — exercise homepage
commit "Add Hevy-style exercise detail screen with history, progress, and how-to." \
  Signal/Signal/Features/Train/ExerciseDetailView.swift \
  Signal/Signal/Features/Train/ExerciseDetailViewModel.swift \
  Signal/Signal/Data/Workout/ExerciseDetailHistoryLoader.swift \
  Signal/Signal/Data/Workout/ExerciseGuideLoader.swift \
  Signal/Signal/Data/Workout/ExerciseVolumeCalculator.swift \
  Signal/Signal/Features/Train/TrainHomeView.swift \
  Signal/Signal/Features/Train/WorkoutExerciseSectionView.swift \
  Signal/Signal/Features/Train/WorkoutHistoryDetailView.swift \
  Signal/Signal/Features/Train/LiveWorkoutCoordinator.swift \
  Signal/Signal/Features/Dashboard/DashboardChartValueStyle.swift \
  Signal/Signal/Resources/HevyExerciseGuides.json \
  Signal/SignalTests/ExerciseDetailHistoryLoaderTests.swift \
  Signal/SignalTests/ExerciseGuideLoaderTests.swift \
  Signal/SignalTests/ExerciseVolumeCalculatorTests.swift \
  scripts/build-hevy-exercise-guides.sh \
  HANDOFF-EXERCISE-HOMEPAGE.md

# Prior parallel work not in A1–A7
commit "Ship exercise swap, coach UAT harness, and supporting train/coach updates." \
  Signal/Signal/Data/Workout/ExerciseSwapCandidateRanker.swift \
  Signal/Signal/Data/Workout/ExerciseSwapLoadPrescription.swift \
  Signal/Signal/Data/Workout/WorkoutSwapFMSelector.swift \
  Signal/Signal/Features/Train/WorkoutSwapSheet.swift \
  Signal/Signal/Features/Diagnostics/CoachUATCatalog.swift \
  Signal/Signal/Features/Diagnostics/CoachUATGrader.swift \
  Signal/Signal/Features/Diagnostics/CoachUATRunPolicy.swift \
  Signal/Signal/Features/Diagnostics/CoachUATRunner.swift \
  Signal/Signal/Features/Diagnostics/CoachUATShareReport.swift \
  Signal/Signal/Features/Diagnostics/DiagnosticsView.swift \
  Signal/Signal/Features/Diagnostics/DiagnosticsViewModel.swift \
  Signal/Signal/Features/Diagnostics/FoundationModelsHealthRunner.swift \
  Signal/Signal/Data/Coach/FoundationModelsInferenceGate.swift \
  Signal/Signal/Data/Calendar/CalendarAlcoholFMClassifier.swift \
  Signal/SignalTests/LiveWorkoutStoreSwapTests.swift \
  Signal/SignalTests/CoachUATDeviceTests.swift \
  Signal/SignalTests/CoachUATFixtureSeeder.swift \
  Signal/SignalTests/CoachUATGraderTests.swift \
  Signal/SignalTests/WorkoutSwapFMSelectorTests.swift \
  Signal/SignalTests/ExerciseSwapCandidateRankerTests.swift \
  Signal/SignalTests/ExerciseSwapLoadPrescriptionTests.swift \
  scripts/run-coach-uat-device.sh \
  HANDOFF-V3M3.md \
  HANDOFF-V3M6.md \
  HANDOFF-V3M7-CALENDAR-DISRUPTOR-INFERENCE.md \
  HANDOFF-V4M5-LIVE-HR-SOURCES.md

# Coordination docs
commit "Record parallel agent integration status and build handover log." \
  PARALLEL-AGENT-PLAN-2026-06-05.md \
  AGENT-BUILD-UPDATES.md

echo "Done. Remaining unstaged:"
git status --short
