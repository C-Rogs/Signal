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
    @Environment(AppLifecycleBroker.self) private var lifecycleBroker

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
        workoutList
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
                        .navigationDestination(for: TrainRoute.self) { trainRoute in
                            exerciseDetailTrainRouteDestination(trainRoute)
                        }
                }
            }
            .onChange(of: scenePhase) { previousPhase, phase in
                TrainWorkoutDiagnostics.record(
                    "activeWorkout scenePhase=\(phase) exercises=\(orderedExercises.count) sets=\(completedSetCount) uiState=\(UIApplication.shared.applicationState.rawValue) trueBackground=\(lifecycleBroker.resolvedIsInTrueBackground)"
                )
                if phase == .active, previousPhase != .active {
                    scheduleDeferredHomeRecovery(from: previousPhase)
                }
            }
            .onChange(of: lifecycleBroker.backgroundFocusDismissGeneration) { _, _ in
                guard coordinator.isViewingActiveWorkout else { return }
                setFieldFocusCoordinator.dismissForSystemOverlay()
                TrainWorkoutDiagnostics.record(
                    "activeWorkout brokerFocusDismiss keyboardVisible=\(lifecycleBroker.isKeyboardVisible)"
                )
            }
            .onAppear {
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
                guard !coordinator.hasStartedWatch(for: session.persistentModelID) else { return }
                coordinator.markWatchStarted(for: session.persistentModelID)
                Task {
                    await watchBridge.ensureWatchWorkoutStarted(for: session, modelContext: modelContext)
                }
            }
            .onDisappear {
                TrainWorkoutDiagnostics.record(
                    "activeWorkout disappear exercises=\(orderedExercises.count) scenePhase=\(scenePhase) viewing=\(coordinator.isViewingActiveWorkout) trueBackground=\(lifecycleBroker.resolvedIsInTrueBackground)"
                )
            }
    }

    @ViewBuilder
    private func exerciseDetailTrainRouteDestination(_ route: TrainRoute) -> some View {
        switch route {
        case .history(let id):
            if let historySession = resolveHistorySession(id: id) {
                WorkoutHistoryDetailView(session: historySession)
            } else {
                ContentUnavailableView("Session not found", systemImage: "questionmark")
            }
        default:
            ContentUnavailableView("Unavailable", systemImage: "questionmark")
        }
    }

    private func resolveHistorySession(id: PersistentIdentifier) -> WorkoutSession? {
        modelContext.model(for: id) as? WorkoutSession
    }

    private func scheduleDeferredHomeRecovery(from previousPhase: ScenePhase) {
        homeForegroundRecoveryTask?.cancel()
        coordinator.isForegroundRecoveryInFlight = true
        homeForegroundRecoveryTask = Task {
            TrainWorkoutDiagnostics.record(
                "homeForegroundReturn scheduled prevPhase=\(previousPhase)"
            )
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard coordinator.isViewingActiveWorkout else {
                coordinator.isForegroundRecoveryInFlight = false
                return
            }
            reloadSessionRecoveryScore()
            refreshWorkoutHints()
            refreshVolumeStats()
            if orderedExercises.isEmpty, !session.exercises.isEmpty {
                coordinator.requestWorkoutSurfaceRefresh(reason: "blankBodyDetected")
            }
            await watchBridge.ensureWatchWorkoutStarted(for: session, modelContext: modelContext)
            coordinator.isForegroundRecoveryInFlight = false
            TrainWorkoutDiagnostics.record(
                "homeForegroundReturn completed gen=\(coordinator.workoutSurfaceGeneration)"
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
