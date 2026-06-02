import Combine
import SwiftData
import SwiftUI

struct WorkoutExerciseSectionView: View {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let lastHint: String?
    let store: LiveWorkoutStore
    let onSupersetScroll: (PersistentIdentifier) -> Void
    let onNeedsRefresh: () -> Void

    @State private var showReplacePicker = false
    @State private var showRemoveConfirm = false
    @State private var showSupersetPicker = false
    @State private var restTick = Date()

    private var sortedSets: [SetEntry] {
        exercise.sets.sorted { $0.setIndex < $1.setIndex }
    }

    private var restRemaining: Int? {
        guard let endsAt = exercise.restTimerEndsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(restTick)))
    }

    private var completionStatus: ExerciseCompletionStatus {
        ExerciseCompletionStatus.status(for: exercise)
    }

    private var setProgress: (done: Int, total: Int) {
        WorkoutSessionCompletionSummary.completedSetCount(in: exercise)
    }

    var body: some View {
        Section {
            ForEach(sortedSets, id: \.persistentModelID) { set in
                SetRowView(
                    set: set,
                    mode: mode,
                    formatter: formatter,
                    onCommit: { fields in
                        try? store.commitSetFields(set, fields: fields)
                        onNeedsRefresh()
                    },
                    onToggleComplete: { completed in
                        try? store.toggleSetComplete(set, exercise: exercise, completed: completed)
                        onNeedsRefresh()
                        if completed, let partner = supersetPartner {
                            onSupersetScroll(partner.persistentModelID)
                        }
                    },
                    onDelete: {
                        try? store.deleteSet(set, from: exercise)
                        onNeedsRefresh()
                    }
                )
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let set = sortedSets[index]
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            restTick = date
        }
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

            restTimerBar
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

    @ViewBuilder
    private var restTimerBar: some View {
        HStack(spacing: 8) {
            if let remaining = restRemaining, remaining > 0 {
                Text("Rest \(remaining)s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color("Primary"))
                Button("Skip") {
                    try? store.stopRestTimer(for: exercise)
                    onNeedsRefresh()
                }
                .font(.caption)
                Button("+15s") {
                    try? store.adjustRestTimer(for: exercise, by: 15)
                    onNeedsRefresh()
                }
                .font(.caption)
                Button("Stop") {
                    try? store.stopRestTimer(for: exercise)
                    onNeedsRefresh()
                }
                .font(.caption)
            } else {
                Button("Start rest") {
                    try? store.startRestTimer(for: exercise)
                    onNeedsRefresh()
                }
                .font(.caption)
                .accessibilityIdentifier("startRest-\(exercise.order)")
            }
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
}
