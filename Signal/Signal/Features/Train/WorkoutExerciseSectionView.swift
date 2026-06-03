import SwiftData
import SwiftUI

struct WorkoutExerciseSectionView: View {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let lastHint: String?
    let store: LiveWorkoutStore
    let modelContext: ModelContext
    let onSupersetScroll: (PersistentIdentifier) -> Void
    let onNeedsRefresh: () -> Void

    @Environment(TrainPreferences.self) private var trainPreferences
    @State private var showReplacePicker = false
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
        Section {
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
            }

            SetTableHeaderView(
                mode: mode,
                massColumnTitle: massColumnTitle,
                distanceColumnTitle: distanceColumnTitle
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 0, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !warmupSets.isEmpty {
                ForEach(warmupSets, id: \.persistentModelID) { set in
                    setRow(for: set)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let set = warmupSets[index]
                        try? store.deleteSet(set, from: exercise)
                    }
                    onNeedsRefresh()
                }
            }

            if !warmupSets.isEmpty, !workingSets.isEmpty {
                workingSetsDivider
            }

            ForEach(workingSets, id: \.persistentModelID) { set in
                setRow(for: set)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let set = workingSets[index]
                    try? store.deleteSet(set, from: exercise)
                }
                onNeedsRefresh()
            }

            Button {
                try? store.addSet(to: exercise)
                onNeedsRefresh()
            } label: {
                Label("Add Set", systemImage: "plus")
            }
        } header: {
            exerciseHeader
        }
        .listSectionSpacing(4)
        .sheet(isPresented: $showReplacePicker) {
            ExercisePickerView { catalog in
                try? store.replaceExercise(
                    exercise,
                    catalogEntry: catalog,
                    exerciseTitle: catalog.canonicalName
                )
                onNeedsRefresh()
            }
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
    }

    @ViewBuilder
    private func setRow(for set: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SetRowView(
                set: set,
                mode: mode,
                formatter: formatter,
                previousHint: previousHint(for: set),
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
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func handleSetCompleteToggle(set: SetEntry, completed: Bool) {
        try? store.toggleSetComplete(set, exercise: exercise, completed: completed)
        onNeedsRefresh()
        if completed {
            if let message = SetCueEvaluator.cue(
                for: set,
                exercise: exercise,
                session: session,
                mode: mode,
                in: modelContext
            ) {
                showCue(message, for: set)
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
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
                        Text(exercise.exerciseTitle)
                            .font(.headline)
                            .foregroundStyle(Color("TextPrimary"))
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
                            Button("Replace exercise") { showReplacePicker = true }
                            Button("Start rest timer") {
                                try? store.startRestTimer(for: exercise)
                                onNeedsRefresh()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(completionColor.opacity(completionStatus == .complete ? 0.1 : 0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        completionColor.opacity(completionStatus == .notStarted ? 0.14 : 0.3),
                        lineWidth: 1
                    )
            }
    }

    private func previousHint(for set: SetEntry) -> String? {
        guard let template = try? LastSessionAutofill.previousSet(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            setIndex: set.setIndex,
            mode: mode,
            in: modelContext
        ) else { return nil }
        return LastSessionAutofill.formatPreviousHint(template, mode: mode, formatter: formatter)
    }

    private func fillPreviousAction(for set: SetEntry) -> (() -> Void)? {
        guard let template = try? LastSessionAutofill.previousSet(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            setIndex: set.setIndex,
            mode: mode,
            in: modelContext
        ) else { return nil }
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
        .hypertrophy
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
