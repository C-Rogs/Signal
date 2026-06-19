import os
import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
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
    @State private var sessionRecoveryScore: RecoveryScore?
    @State private var sessionPersonalReadiness: PersonalReadinessProfile?
    @State private var deloadChipTitle: String?
    @State private var hintCache = ExerciseSessionHintCache()
    @State private var volumeKg = 0.0
    @State private var completedSetCount = 0
    @State private var restTimerCoordinator = ActiveWorkoutRestTimerCoordinator()
    @State private var exerciseDetailRoute: ExerciseDetailRoute?
    @State private var setFieldFocusCoordinator = TrainSetFieldFocusCoordinator()
    @State private var listRecoveryToken = 0
    @State private var hideBodyForSnapshot = false
    @State private var didInitialWatchStart = false
    @State private var homeForegroundRecoveryTask: Task<Void, Never>?

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
        Group {
            if hideBodyForSnapshot {
                screenBackground.ignoresSafeArea()
            } else {
                workoutList
            }
        }
            .environment(setFieldFocusCoordinator)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActiveWorkoutRestTimerLayer(
                    coordinator: restTimerCoordinator,
                    exercises: orderedExercises,
                    scenePhase: scenePhase,
                    watchBridge: watchBridge,
                    store: store,
                    onCoordinatorRefresh: { coordinator.refresh() }
                )
            }
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                workoutToolbar
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        setFieldFocusCoordinator.requestDismiss()
                        TrainKeyboard.dismiss()
                    }
                }
            }
            .modifier(ActiveWorkoutDialogsModifier(
                showDiscardConfirm: $showDiscardConfirm,
                showFinishIncompleteConfirm: $showFinishIncompleteConfirm,
                showFinishEmptyConfirm: $showFinishEmptyConfirm,
                incompleteExerciseCount: incompleteExerciseCount,
                onDiscard: discardWorkout,
                onFinish: finishWorkout
            ))
            .sheet(isPresented: $showAddExercise) { addExerciseSheet }
            .sheet(item: $exerciseDetailRoute) { route in
                NavigationStack {
                    ExerciseDetailView(route: route)
                }
            }
            .onChange(of: scenePhase) { previousPhase, phase in
                TrainWorkoutDiagnostics.record(
                    "activeWorkout scenePhase=\(phase) exercises=\(orderedExercises.count) sets=\(completedSetCount) uiState=\(UIApplication.shared.applicationState.rawValue) trueBackground=\(TrainApplicationLifecycle.resolvedIsInTrueBackground) hideBody=\(hideBodyForSnapshot)"
                )
                if phase == .active, previousPhase != .active {
                    restoreWorkoutBodyImmediately(reason: "scenePhaseActive prev=\(previousPhase)")
                    scheduleDeferredHomeRecovery(from: previousPhase)
                }
            }
            .onAppear {
                hideBodyForSnapshot = false
                reloadSessionRecoveryScore()
                refreshWorkoutHints()
                refreshVolumeStats()
                watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
                TrainWorkoutDiagnostics.record(
                    "activeWorkout appear exercises=\(orderedExercises.count) session=\(session.persistentModelID)"
                )
                Log.ui.info(
                    "active workout appeared exercises=\(orderedExercises.count, privacy: .public) sessionID=\(String(describing: session.persistentModelID), privacy: .public)"
                )
                guard !didInitialWatchStart else { return }
                didInitialWatchStart = true
                Task {
                    await watchBridge.ensureWatchWorkoutStarted(for: session, modelContext: modelContext)
                }
            }
            .onDisappear {
                TrainWorkoutDiagnostics.record(
                    "activeWorkout disappear exercises=\(orderedExercises.count) scenePhase=\(scenePhase) viewing=\(coordinator.isViewingActiveWorkout) trueBackground=\(TrainApplicationLifecycle.resolvedIsInTrueBackground)"
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                guard coordinator.isViewingActiveWorkout else { return }
                hideBodyForSnapshot = true
                coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
                setFieldFocusCoordinator.dismissForSystemOverlay()
                TrainKeyboard.dismiss()
                TrainWorkoutDiagnostics.record(
                    "activeWorkout didEnterBackground hideBody keyboardVisible=\(TrainApplicationLifecycle.isKeyboardVisible)"
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard coordinator.isViewingActiveWorkout else { return }
                restoreWorkoutBodyImmediately(reason: "willEnterForeground")
                TrainWorkoutDiagnostics.record("activeWorkout willEnterForeground restoreBody")
            }
    }

    private func restoreWorkoutBodyImmediately(reason: String) {
        hideBodyForSnapshot = false
        listRecoveryToken += 1
        TrainWorkoutDiagnostics.record(
            "activeWorkout restoreBody reason=\(reason) token=\(listRecoveryToken) exercises=\(orderedExercises.count)"
        )
    }

    private func scheduleDeferredHomeRecovery(from previousPhase: ScenePhase) {
        homeForegroundRecoveryTask?.cancel()
        homeForegroundRecoveryTask = Task {
            TrainWorkoutDiagnostics.record(
                "homeForegroundReturn scheduled prevPhase=\(previousPhase) needsRefresh=\(coordinator.workoutSurfaceNeedsRefresh)"
            )
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard coordinator.isViewingActiveWorkout else { return }
            refreshWorkoutHints()
            refreshVolumeStats()
            if coordinator.workoutSurfaceNeedsRefresh {
                coordinator.requestWorkoutSurfaceRefresh(reason: "homeForegroundReturn")
            }
            await watchBridge.ensureWatchWorkoutStarted(for: session, modelContext: modelContext)
            TrainWorkoutDiagnostics.record(
                "homeForegroundReturn completed token=\(listRecoveryToken) gen=\(coordinator.workoutSurfaceGeneration)"
            )
        }
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
        Log.workout.debug(
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

    private var workoutList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    WorkoutLiveSummaryBar(
                        sessionStartTime: session.startTime,
                        volumeKg: volumeKg,
                        completedSetCount: completedSetCount,
                        formatter: formatter,
                        watchBridge: watchBridge,
                        recoveryChipTitle: lowRecoveryChipTitle,
                        deloadChipTitle: deloadChipTitle
                    )
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainSurfaceCard()

                    ForEach(orderedExercises, id: \.persistentModelID) { exercise in
                        WorkoutExerciseSectionView(
                            exercise: exercise,
                            session: session,
                            mode: ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry),
                            formatter: formatter,
                            lastHint: hintCache.lastHint(for: exercise),
                            hintCache: hintCache,
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
                                refreshWorkoutHints()
                                refreshVolumeStats()
                            },
                            onRestTimerStarted: restTimerCoordinator.acknowledgeRestTimerStarted,
                            onOpenExerciseDetail: { route in
                                TrainWorkoutDiagnostics.record("openExerciseDetail title=\(route.exerciseTitle)")
                                exerciseDetailRoute = route
                            }
                        )
                        .id(exercise.persistentModelID)
                    }
                    .id(listRecoveryToken)

                    Button {
                        showAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color("Primary"))
                    .accessibilityIdentifier("addExerciseButton")
                }
                .padding(.horizontal, TrainChrome.horizontalPadding)
                .padding(.vertical, 8)
                .padding(.bottom, restTimerCoordinator.showsRestBar ? 4 : 8)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.immediately)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(listRecoveryToken)
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
            Menu {
                Button("Minimize workout") {
                    coordinator.minimizeWorkout(source: "toolbarMenu")
                }
                Button("Discard workout", role: .destructive) {
                    showDiscardConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout actions")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") {
                if orderedExercises.isEmpty {
                    showFinishEmptyConfirm = true
                } else {
                    attemptFinishWorkout()
                }
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("finishWorkoutButton")
        }
    }

    private var addExerciseSheet: some View {
        ExercisePickerView { catalog in
            _ = try? store.addExercise(
                to: session,
                catalogEntry: catalog,
                exerciseTitle: catalog.canonicalName
            )
            coordinator.refresh()
            refreshWorkoutHints()
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private func refreshWorkoutHints() {
        hintCache.warm(exercises: orderedExercises, formatter: formatter, in: modelContext)
    }

    private func refreshVolumeStats() {
        let stats = WorkoutLiveSummary.volumeStats(for: session)
        volumeKg = stats.volumeKg
        completedSetCount = stats.completedSetCount
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
        restTimerCoordinator.markUserSkippedFeedback()
        TrainFeedback.shared.play(.workoutFinish)
        watchBridge.endWatchWorkout()
        do {
            try store.finishSession(session)
            ExerciseProgressStore.recordFinishedSession(session, in: modelContext)
            hintCache.invalidate()
            coordinator.presentWellness(for: session)
            coordinator.refresh()
            coordinator.resetTrainNavigation(reason: "finishWorkout")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        restTimerCoordinator.markUserSkippedFeedback()
        watchBridge.endWatchWorkout()
        do {
            try store.discardSession(session)
            hintCache.invalidate()
            coordinator.resetTrainNavigation(reason: "discardWorkout")
            coordinator.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
