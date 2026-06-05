import Combine
import os
import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UnitPreferences.self) private var unitPreferences
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(LiveWorkoutWatchBridge.self) private var watchBridge
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var session: WorkoutSession

    @State private var showDiscardConfirm = false
    @State private var showFinishIncompleteConfirm = false
    @State private var incompleteExerciseCount = 0
    @State private var showFinishEmptyConfirm = false
    @State private var showAddExercise = false
    @State private var errorMessage: String?
    @State private var tick = Date()
    @State private var dynamicRestState = DynamicRestState()
    @State private var dynamicRestNotice: String?
    @State private var sessionRecoveryScore: RecoveryScore?
    @State private var sessionPersonalReadiness: PersonalReadinessProfile?
    @State private var deloadChipTitle: String?

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
                        autoregulationNotice: dynamicRestNotice,
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
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                tick = date
                applyDynamicRestExtension(at: date)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    try? modelContext.save()
                }
                if phase == .active {
                    reloadSessionRecoveryScore()
                }
                if TrainScenePhaseKeyboardPolicy.shouldReleaseSetFieldFocus(for: phase) {
                    TrainKeyboard.dismiss()
                }
                if TrainScenePhaseKeyboardPolicy.shouldDismissKeyboardOnResume(for: phase) {
                    TrainKeyboard.dismiss()
                }
            }
            .onAppear {
                coordinator.isViewingActiveWorkout = true
                reloadSessionRecoveryScore()
                watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
                Task {
                    await watchBridge.ensureWatchWorkoutStarted(for: session, modelContext: modelContext)
                }
            }
            .onDisappear { coordinator.isViewingActiveWorkout = false }
    }

    private var recoveryBandContext: RecoveryBandContext? {
        guard let sessionRecoveryScore else { return nil }
        return RecoveryBandContext(score: sessionRecoveryScore, profile: sessionPersonalReadiness)
    }

    private var lowRecoveryChipTitle: String? {
        guard let recoveryBandContext else { return nil }
        return LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: recoveryBandContext)
    }

    private func reloadSessionRecoveryScore() {
        let bundle = RecoveryEngine.todayReadinessBundle(in: modelContext)
        sessionRecoveryScore = bundle.score
        sessionPersonalReadiness = bundle.profile
        deloadChipTitle = DeloadSuggestionReader.isDeloadActive(in: modelContext)
            ? "High load week"
            : nil
        let context = RecoveryBandContext(score: bundle.score, profile: bundle.profile)
        let chip = LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: context) ?? "none"
        Log.workout.info(
            "workout session recovery score=\(bundle.score.value, format: .fixed(precision: 0), privacy: .public) chip=\(chip, privacy: .public)"
        )
    }

    private var defaultSessionRecoveryScore: RecoveryScore {
        RecoveryScore(
            value: 50,
            hrvClassification: .insufficientData,
            hrvAnalysis: nil,
            rhrDelta: nil,
            sleepDelta: nil,
            confidence: .low,
            breakdown: RecoveryScoreBreakdown(hrvTerm: 0, rhrTerm: 0, sleepTerm: 0, total: 50),
            todayHRV: nil,
            todayRestingHR: nil
        )
    }

    private var liveSummary: WorkoutLiveSummary {
        _ = tick
        return WorkoutLiveSummary.compute(
            for: session,
            heartRateBPM: watchBridge.latestHeartRateBPM
        )
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
                    WorkoutLiveSummaryBar(
                        summary: liveSummary,
                        formatter: formatter,
                        recoveryChipTitle: lowRecoveryChipTitle,
                        deloadChipTitle: deloadChipTitle,
                        heartRateUI: watchBridge.heartRateUIState(now: tick)
                    )
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
                        recoveryScore: sessionRecoveryScore ?? defaultSessionRecoveryScore,
                        personalReadiness: sessionPersonalReadiness,
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
                            reloadSessionRecoveryScore()
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
            .scrollDismissesKeyboard(.interactively)
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

    private func applyDynamicRestExtension(at now: Date) {
        guard let activeRest = activeRestTimer,
              let restEndsAt = activeRest.exercise.restTimerEndsAt
        else {
            if dynamicRestNotice != nil {
                dynamicRestNotice = nil
            }
            if dynamicRestState.trackedExerciseID != nil {
                dynamicRestState = DynamicRestState()
            }
            return
        }

        let exerciseID = String(describing: activeRest.exercise.persistentModelID)
        let input = DynamicRestTimerEvaluator.Input(
            exerciseID: exerciseID,
            heartRateBPM: watchBridge.latestHeartRateBPM,
            heartRateSampledAt: watchBridge.lastHeartRateAt,
            now: now,
            restEndsAt: restEndsAt,
            state: dynamicRestState
        )
        guard let decision = DynamicRestTimerEvaluator.evaluate(input) else { return }

        dynamicRestState = decision.newState
        dynamicRestNotice = decision.notice
        do {
            try store.adjustRestTimer(for: activeRest.exercise, by: decision.extensionSeconds)
            coordinator.refresh()
            Log.workout.info(
                "dynamic rest extended seconds=\(decision.extensionSeconds, privacy: .public) bpm=\(watchBridge.latestHeartRateBPM ?? 0, privacy: .public) extensions=\(decision.newState.extensionCount, privacy: .public)"
            )
        } catch {
            Log.workout.error(
                "dynamic rest extend failed: \(String(describing: error), privacy: .public)"
            )
        }
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
        watchBridge.endWatchWorkout()
        do {
            try store.finishSession(session)
            ExerciseProgressStore.recordFinishedSession(session, in: modelContext)
            coordinator.presentWellness(for: session)
            coordinator.isViewingActiveWorkout = false
            coordinator.refresh()
            coordinator.resetTrainNavigation()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        watchBridge.endWatchWorkout()
        do {
            try store.discardSession(session)
            coordinator.resetTrainNavigation()
            coordinator.refresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
