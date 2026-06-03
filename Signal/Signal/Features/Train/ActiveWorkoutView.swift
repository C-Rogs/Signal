import Combine
import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UnitPreferences.self) private var unitPreferences
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var session: WorkoutSession

    @State private var wellnessMuscles: [Muscle] = []
    @State private var showDiscardConfirm = false
    @State private var showFinishIncompleteConfirm = false
    @State private var incompleteExerciseCount = 0
    @State private var showFinishEmptyConfirm = false
    @State private var showWellness = false
    @State private var showAddExercise = false
    @State private var errorMessage: String?
    @State private var tick = Date()

    private var store: LiveWorkoutStore {
        LiveWorkoutStore(context: modelContext)
    }

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    private var orderedExercises: [WorkoutExercise] {
        session.exercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        workoutList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let activeRest = activeRestTimer {
                    FloatingRestTimerBar(
                        exerciseTitle: activeRest.exercise.exerciseTitle,
                        remainingSeconds: activeRest.remaining,
                        onSkip: { stopRest(for: activeRest.exercise) },
                        onSubtract15: { adjustRest(for: activeRest.exercise, by: -15) },
                        onAdd15: { adjustRest(for: activeRest.exercise, by: 15) }
                    )
                }
            }
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { workoutToolbar }
            .modifier(ActiveWorkoutDialogsModifier(
                showDiscardConfirm: $showDiscardConfirm,
                showFinishIncompleteConfirm: $showFinishIncompleteConfirm,
                showFinishEmptyConfirm: $showFinishEmptyConfirm,
                incompleteExerciseCount: incompleteExerciseCount,
                onDiscard: discardWorkout,
                onFinish: finishWorkout
            ))
            .sheet(isPresented: $showAddExercise) { addExerciseSheet }
            .sheet(isPresented: $showWellness) { wellnessSheet }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                tick = date
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                try? modelContext.save()
            }
            .onAppear { coordinator.isViewingActiveWorkout = true }
            .onDisappear { coordinator.isViewingActiveWorkout = false }
    }

    private var liveSummary: WorkoutLiveSummary {
        _ = tick
        return WorkoutLiveSummary.compute(for: session)
    }

    private var workoutList: some View {
        ScrollViewReader { proxy in
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    WorkoutLiveSummaryBar(summary: liveSummary, formatter: formatter)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color("Surface"))
                }

                ForEach(orderedExercises, id: \.persistentModelID) { exercise in
                    WorkoutExerciseSectionView(
                        exercise: exercise,
                        session: session,
                        mode: ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry),
                        formatter: formatter,
                        lastHint: lastHint(for: exercise),
                        store: store,
                        modelContext: modelContext,
                        onSupersetScroll: { id in
                            withAnimation {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        },
                        onNeedsRefresh: {
                            coordinator.refresh()
                            tick = Date()
                        }
                    )
                    .id(exercise.persistentModelID)
                }
                .onMove { source, destination in
                    try? store.reorderExercises(in: session, fromOffsets: source, toOffset: destination)
                    coordinator.refresh()
                }

                Section {
                    Button {
                        showAddExercise = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addExerciseButton")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .onAppear {
                if let target = coordinator.consumeScrollTarget() {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .onChange(of: coordinator.scrollToExerciseID) { _, newValue in
                if let newValue {
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                    _ = coordinator.consumeScrollTarget()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var workoutToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 16) {
                Button("Minimize") { dismiss() }
                Button("Discard") { showDiscardConfirm = true }
                    .foregroundStyle(.red)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") {
                if orderedExercises.isEmpty {
                    showFinishEmptyConfirm = true
                } else {
                    attemptFinishWorkout()
                }
            }
            .accessibilityIdentifier("finishWorkoutButton")
        }
    }

    private var addExerciseSheet: some View {
        ExercisePickerView { catalog in
            try? store.addExercise(
                to: session,
                catalogEntry: catalog,
                exerciseTitle: catalog.canonicalName
            )
            coordinator.refresh()
        }
    }

    private var wellnessSheet: some View {
        WellnessCaptureView(
            muscles: wellnessMuscles,
            onSave: { energy, mood, stress, soreness, notes in
                saveWellness(energy: energy, mood: mood, stress: stress, soreness: soreness, notes: notes)
            },
            onSkip: { dismissAfterFinish() }
        )
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var activeRestTimer: (exercise: WorkoutExercise, remaining: Int)? {
        _ = tick
        let now = Date()
        var best: (WorkoutExercise, Date)?
        for exercise in orderedExercises {
            guard let endsAt = exercise.restTimerEndsAt, endsAt > now else { continue }
            if let current = best {
                if endsAt > current.1 {
                    best = (exercise, endsAt)
                }
            } else {
                best = (exercise, endsAt)
            }
        }
        guard let best else { return nil }
        return (best.0, max(0, Int(best.1.timeIntervalSince(now))))
    }

    private func stopRest(for exercise: WorkoutExercise) {
        try? store.stopRestTimer(for: exercise)
        coordinator.refresh()
        tick = Date()
    }

    private func adjustRest(for exercise: WorkoutExercise, by seconds: Int) {
        try? store.adjustRestTimer(for: exercise, by: seconds)
        coordinator.refresh()
        tick = Date()
    }

    private func lastHint(for exercise: WorkoutExercise) -> String? {
        try? LastSessionAutofill.lastSessionHint(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            mode: ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry),
            in: modelContext,
            formatter: formatter
        )
    }

    private func attemptFinishWorkout() {
        let incomplete = WorkoutSessionCompletionSummary.incompleteExercises(in: session)
        if incomplete.isEmpty {
            finishWorkout()
        } else {
            incompleteExerciseCount = incomplete.count
            showFinishIncompleteConfirm = true
        }
    }

    private func finishWorkout() {
        do {
            wellnessMuscles = WorkoutMusclesWorked.muscles(for: session)
            try store.finishSession(session)
            coordinator.isViewingActiveWorkout = false
            coordinator.refresh()
            showWellness = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        do {
            try store.discardSession(session)
            coordinator.resetTrainNavigation()
            coordinator.refresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveWellness(
        energy: Int,
        mood: Int,
        stress: Int,
        soreness: [String: Int],
        notes: String?
    ) {
        do {
            let entry = try store.saveWellness(
                for: session,
                energy: energy,
                mood: mood,
                stress: stress,
                sorenessByMuscleRaw: soreness,
                notes: notes
            )
            let vectorStore = SwiftDataVectorStore(context: modelContext)
            let embedding = EmbeddingBackend.makeService()
            Task {
                await WellnessNoteIndexer.indexNotesIfNeeded(
                    entry: entry,
                    store: vectorStore,
                    service: embedding
                )
            }
            dismissAfterFinish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissAfterFinish() {
        coordinator.resetTrainNavigation()
        coordinator.refresh()
        dismiss()
    }
}
