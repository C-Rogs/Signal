import os
import SwiftData
import SwiftUI

struct WorkoutExerciseSectionView: View {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let lastHint: String?
    let hintCache: ExerciseSessionHintCache
    let recoveryScore: RecoveryScore
    let personalReadiness: PersonalReadinessProfile?
    let store: LiveWorkoutStore
    let modelContext: ModelContext
    let onSupersetScroll: (PersistentIdentifier) -> Void
    let onNeedsRefresh: () -> Void
    let onRestTimerStarted: (WorkoutExercise) -> Void
    let onOpenExerciseDetail: (ExerciseDetailRoute) -> Void

    @Environment(TrainPreferences.self) private var trainPreferences
    @Environment(LiveWorkoutWatchBridge.self) private var watchBridge
    @State private var showReplacePicker = false
    @State private var showSwapSheet = false
    @State private var dismissedWarmupSuggestion = false
    @State private var showRemoveConfirm = false
    @State private var showSupersetPicker = false
    @State private var activeCues: [PersistentIdentifier: String] = [:]
    @State private var cueDismissTask: Task<Void, Never>?

    private var sortedSets: [SetEntry] {
        exercise.sets.sorted { $0.setIndex < $1.setIndex }
    }

    private var warmupSets: [SetEntry] {
        sortedSets.filter { WorkoutSetType(storageValue: $0.setType) == .warmup }
    }

    private var workingSets: [SetEntry] {
        sortedSets.filter { WorkoutSetType(storageValue: $0.setType) != .warmup }
    }

    private var completionStatus: ExerciseCompletionStatus {
        ExerciseCompletionStatus.status(for: exercise)
    }

    private var setProgress: (done: Int, total: Int) {
        WorkoutSessionCompletionSummary.completedSetCount(in: exercise)
    }

    private var massColumnTitle: String {
        formatter.massUnit == .kilograms ? "KG" : "LB"
    }

    private var distanceColumnTitle: String {
        formatter.distanceUnit == .kilometers ? "KM" : "MI"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exerciseHeader

            if let recommendation = warmupRecommendation {
                WarmupSuggestionBannerView(
                    summary: recommendation.summary,
                    onAdd: {
                        try? store.addSuggestedWarmupSets(to: exercise, recommendation: recommendation)
                        dismissedWarmupSuggestion = true
                        onNeedsRefresh()
                    },
                    onDismiss: {
                        dismissedWarmupSuggestion = true
                    }
                )
                .padding(.horizontal, 4)
            }

            SetTableHeaderView(
                mode: mode,
                massColumnTitle: massColumnTitle,
                distanceColumnTitle: distanceColumnTitle
            )
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !warmupSets.isEmpty {
                ForEach(warmupSets, id: \.persistentModelID) { set in
                    setRow(for: set)
                }
            }

            if !warmupSets.isEmpty, !workingSets.isEmpty {
                workingSetsDivider
            }

            ForEach(workingSets, id: \.persistentModelID) { set in
                setRow(for: set)
            }

            Button {
                try? store.addSet(to: exercise)
                onNeedsRefresh()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.body.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .trainSurfaceCard()
        .sheet(isPresented: $showReplacePicker) {
            ExercisePickerView { catalog in
                try? store.replaceExercise(
                    exercise,
                    catalogEntry: catalog,
                    exerciseTitle: catalog.canonicalName,
                    recoveryScore: recoveryScore,
                    personalReadiness: personalReadiness,
                    deloadActive: DeloadSuggestionReader.isDeloadActive(in: modelContext)
                )
                onNeedsRefresh()
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            WorkoutSwapSheet(
                exercise: exercise,
                store: store,
                recoveryScore: recoveryScore,
                personalReadiness: personalReadiness,
                onApplied: onNeedsRefresh
            )
        }
        .confirmationDialog(
            "Remove exercise?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                try? store.removeExercise(exercise, from: session)
                onNeedsRefresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Logged sets for this exercise will be deleted.")
        }
        .confirmationDialog("Pair with", isPresented: $showSupersetPicker, titleVisibility: .visible) {
            ForEach(supersetCandidates, id: \.persistentModelID) { candidate in
                Button(candidate.exerciseTitle) {
                    try? store.linkSuperset(exercise, candidate)
                    onNeedsRefresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .goalDidChange)) { _ in
            dismissedWarmupSuggestion = false
        }
    }

    @ViewBuilder
    private func setRow(for set: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SetRowView(
                set: set,
                mode: mode,
                formatter: formatter,
                previousHint: hintCache.previousHint(for: exercise, setIndex: set.setIndex),
                onFillPrevious: fillPreviousAction(for: set),
                onActivate: {
                    dismissAllCues()
                    try? store.activateSet(set)
                },
                onCommit: { fields in
                    dismissAllCues()
                    try? store.commitSetFields(set, fields: fields)
                    onNeedsRefresh()
                },
                onToggleComplete: { completed in
                    dismissAllCues()
                    handleSetCompleteToggle(set: set, completed: completed)
                },
                onDelete: {
                    dismissAllCues()
                    try? store.deleteSet(set, from: exercise)
                    onNeedsRefresh()
                }
            )
            if let cue = activeCues[set.persistentModelID] {
                SetCueBannerView(message: cue)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: activeCues[set.persistentModelID])
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func handleSetCompleteToggle(set: SetEntry, completed: Bool) {
        try? store.toggleSetComplete(set, exercise: exercise, completed: completed)
        onNeedsRefresh()
        if completed {
            if WorkoutSetType(storageValue: set.setType) != .warmup {
                let tier = SetCueEvaluator.tier(
                    for: set,
                    exercise: exercise,
                    session: session,
                    mode: mode,
                    in: modelContext
                )
                switch tier {
                case .smashed, .strongPR, .smallPR:
                    TrainFeedback.shared.play(.prCelebration)
                default:
                    TrainFeedback.shared.play(.setComplete)
                }
            }
            if exercise.autoStartRestOnSetComplete {
                onRestTimerStarted(exercise)
            }
            let tierMessage = SetCueEvaluator.cue(
                for: set,
                exercise: exercise,
                session: session,
                mode: mode,
                in: modelContext
            )
            let loadNudge = loadNudgeAfterSet(set)
            let now = Date()
            let heartRateBPM = watchBridge.latestHeartRateBPM
            let heartRateSampledAt = watchBridge.lastHeartRateAt
            if let message = LiveSetCueComposer.compose(
                tierMessage: tierMessage,
                loadNudge: loadNudge,
                heartRateBPM: heartRateBPM,
                heartRateSampledAt: heartRateSampledAt,
                now: now
            ) {
                if let loadNudge {
                    Log.workout.debug("load autoregulation nudge=\(loadNudge, privacy: .public)")
                }
                if let hrNudge = LiveHRCueEvaluator.restNudgeAfterSet(
                    bpm: heartRateBPM,
                    sampledAt: heartRateSampledAt,
                    now: now
                ) {
                    Log.workout.debug("live HR set cue nudge=\(hrNudge, privacy: .public)")
                }
                showCue(message, for: set)
            } else if WorkoutSetType(storageValue: set.setType) != .warmup,
                      let heartRateBPM
            {
                let ageSeconds = heartRateSampledAt.map { now.timeIntervalSince($0) }
                Log.workout.debug(
                    "live HR set cue suppressed bpm=\(heartRateBPM, privacy: .public) ageSeconds=\(ageSeconds ?? -1, privacy: .public)"
                )
            }
            if let partner = supersetPartner {
                onSupersetScroll(partner.persistentModelID)
            }
        } else {
            dismissCue(for: set)
        }
    }

    private func showCue(_ message: String, for set: SetEntry) {
        let setID = set.persistentModelID
        cueDismissTask?.cancel()
        activeCues[setID] = message
        cueDismissTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            if activeCues[setID] == message {
                activeCues.removeValue(forKey: setID)
            }
        }
    }

    private func dismissCue(for set: SetEntry) {
        activeCues.removeValue(forKey: set.persistentModelID)
        if activeCues.isEmpty {
            cueDismissTask?.cancel()
            cueDismissTask = nil
        }
    }

    private func dismissAllCues() {
        cueDismissTask?.cancel()
        cueDismissTask = nil
        activeCues.removeAll()
    }

    private func loadNudgeAfterSet(_ set: SetEntry) -> String? {
        guard mode == .strength else { return nil }
        let snapshot = SetCueSnapshot(set: set)
        guard !snapshot.isWarmup else { return nil }
        let targetRIR = ProfileGoalRepository.targetRIR(in: modelContext)
        let lastTemplate = try? LastSessionAutofill.previousSet(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            setIndex: set.setIndex,
            mode: mode,
            in: modelContext
        )
        let lastSessionSet = lastTemplate.map(SetCueSnapshot.init(template:))
        let input = LiveLoadCueInput(
            recoveryScore: recoveryScore,
            personalReadiness: personalReadiness,
            completedSet: snapshot,
            targetRIR: targetRIR,
            targetReps: CueEngine.targetReps(lastSessionSet: lastSessionSet)
        )
        return LiveLoadCueEvaluator.nudge(for: input)
    }

    private var workingSetsDivider: some View {
        HStack {
            Rectangle()
                .fill(Color("TextSecondary").opacity(0.2))
                .frame(height: 1)
            Text("Working sets")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
            Rectangle()
                .fill(Color("TextSecondary").opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ExerciseIllustrationView(
                    catalogEntry: exercise.catalogEntry,
                    title: exercise.exerciseTitle,
                    compact: true
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Button {
                            onOpenExerciseDetail(.from(exercise: exercise))
                        } label: {
                            Text(exercise.exerciseTitle)
                                .font(.headline)
                                .foregroundStyle(Color("TextPrimary"))
                        }
                        .buttonStyle(.plain)
                        if exercise.supersetId != nil {
                            Text("Superset")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color("Primary").opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 0)
                        if setProgress.total > 0 {
                            Text("\(setProgress.done)/\(setProgress.total)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(completionColor)
                        }
                        Menu {
                            Button("Swap with Signal") { showSwapSheet = true }
                            Button("Replace Exercise") { showReplacePicker = true }
                            Button("Start rest timer") {
                                try? store.startRestTimer(for: exercise)
                                onNeedsRefresh()
                                TrainFeedback.shared.play(.primaryTap)
                                onRestTimerStarted(exercise)
                            }
                            if exercise.supersetId == nil {
                                Button("Add to superset") { showSupersetPicker = true }
                            } else {
                                Button("Break superset") {
                                    try? store.breakSuperset(for: exercise, in: session)
                                    onNeedsRefresh()
                                }
                            }
                            Button("Remove exercise", role: .destructive) {
                                if exercise.sets.contains(where: { $0.isCompleted || $0.hasBeenEdited }) {
                                    showRemoveConfirm = true
                                } else {
                                    try? store.removeExercise(exercise, from: session)
                                    onNeedsRefresh()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(Color("TextSecondary"))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("exerciseMenu-\(exercise.order)")
                    }

                    if let catalog = exercise.catalogEntry {
                        MuscleChipRow(
                            primary: catalog.primaryMuscles,
                            secondary: catalog.secondaryMuscles
                        )
                    }
                }
            }

            if let lastHint {
                Text(lastHint)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .textCase(nil)
    }

    private var completionColor: Color {
        switch completionStatus {
        case .complete: Color("Positive")
        case .inProgress: Color("Warning")
        case .notStarted: Color("TextSecondary")
        }
    }

    private var headerBackground: some View {
        completionColor.opacity(completionStatus == .complete ? 0.08 : 0.04)
    }

    private func fillPreviousAction(for set: SetEntry) -> (() -> Void)? {
        guard let template = hintCache.template(for: exercise, setIndex: set.setIndex) else { return nil }
        return {
            try? store.commitSetFields(
                set,
                fields: SetFieldCommit(
                    setType: template.setType,
                    weightKg: template.weightKg,
                    reps: template.reps,
                    distanceKm: template.distanceKm,
                    durationSeconds: template.durationSeconds,
                    rpe: nil
                )
            )
            onNeedsRefresh()
        }
    }

    private var supersetCandidates: [WorkoutExercise] {
        session.exercises
            .filter { $0.persistentModelID != exercise.persistentModelID && $0.supersetId == nil }
            .sorted { $0.order < $1.order }
    }

    private var supersetPartner: WorkoutExercise? {
        guard let id = exercise.supersetId else { return nil }
        return session.exercises.first {
            $0.supersetId == id && $0.persistentModelID != exercise.persistentModelID
        }
    }

    private var warmupRecommendation: WarmupRecommendation? {
        guard !dismissedWarmupSuggestion else { return nil }
        let anchor = anchorWorkingSetFields()
        return WarmupRecommendationEngine.recommend(
            WarmupRecommendationInput(
                enabled: trainPreferences.suggestWarmupSets,
                mode: mode,
                movementPattern: exercise.catalogEntry?.movementPattern,
                exerciseOrder: exercise.order,
                goal: trainingGoal,
                anchorWeightKg: anchor.weightKg,
                anchorReps: anchor.reps,
                alreadyHasWarmupSets: !warmupSets.isEmpty
            )
        )
    }

    private var trainingGoal: GoalType {
        ProfileGoalRepository.primaryGoal(in: modelContext)
    }

    private func anchorWorkingSetFields() -> (weightKg: Double?, reps: Int?) {
        if let set = workingSets.first(where: { $0.weightKg != nil || $0.reps != nil }) {
            return (set.weightKg, set.reps)
        }
        if let set = sortedSets.first(where: { $0.weightKg != nil || $0.reps != nil }) {
            return (set.weightKg, set.reps)
        }
        if let template = try? LastSessionAutofill.templates(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            mode: mode,
            in: modelContext
        ).first {
            return (template.weightKg, template.reps)
        }
        return (nil, nil)
    }
}
