import Foundation
import os
import Observation
import SwiftData
import SwiftUI

struct ExerciseDetailRoute: Hashable, Identifiable {
    var catalogID: PersistentIdentifier?
    var exerciseTitle: String

    var id: String {
        if let catalogID {
            return "catalog-\(String(describing: catalogID))"
        }
        return "title-\(exerciseTitle)"
    }

    static func from(exercise: WorkoutExercise) -> ExerciseDetailRoute {
        ExerciseDetailRoute(
            catalogID: exercise.catalogEntry?.persistentModelID,
            exerciseTitle: exercise.exerciseTitle
        )
    }
}

enum TrainRoute: Hashable {
    case activeWorkout(PersistentIdentifier)
    case history(PersistentIdentifier)
    case editRoutine(PersistentIdentifier?)
    case exerciseDetail(ExerciseDetailRoute)

    var diagnosticLabel: String {
        switch self {
        case .activeWorkout:
            return "activeWorkout"
        case .history:
            return "history"
        case .editRoutine:
            return "editRoutine"
        case .exerciseDetail(let route):
            return "exerciseDetail(\(route.exerciseTitle))"
        }
    }
}

@MainActor
@Observable
final class LiveWorkoutCoordinator {
    var activeSession: WorkoutSession?
    var pendingTrainRoute: TrainRoute?
    var presentedWorkoutSessionID: PersistentIdentifier?
    var workoutSurfaceGeneration = 0
    var workoutSurfaceNeedsRefresh = false
    var scrollToExerciseID: PersistentIdentifier?
    var collapseWorkoutNavigationOnNextTrainAppear = true
    var isViewingActiveWorkout = false
    var isForegroundRecoveryInFlight = false
    var trainNavigationResetToken = 0
    var stripActiveWorkoutRouteToken = 0
    var pendingHealthKitWriteNote: String?
    var pendingWellnessSessionID: PersistentIdentifier?
    var pendingWellnessMuscles: [Muscle] = []

    @ObservationIgnored private var lastRecordedScenePhase: ScenePhase = .active
    @ObservationIgnored private var didStartWatchForSessionIDs: Set<PersistentIdentifier> = []

    private var modelContext: ModelContext?
    private var store: LiveWorkoutStore?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        store = LiveWorkoutStore(context: modelContext)
        if LiveWorkoutCoordinatorLaunchState.collapseNavigationOnNextTrainAppear {
            collapseWorkoutNavigationOnNextTrainAppear = true
            LiveWorkoutCoordinatorLaunchState.collapseNavigationOnNextTrainAppear = false
        }
        refresh()
    }

    func refresh() {
        guard let store else { return }
        do {
            activeSession = try store.activeSession()
        } catch {
            Log.workout.error("active session fetch failed: \(String(describing: error), privacy: .public)")
            activeSession = nil
        }
        AppLifecycleBroker.shared.isLiveWorkoutSessionInProgress = activeSession != nil
    }

    func resumeWorkout() {
        refresh()
        guard let session = activeSession else {
            Log.workout.info("resume requested but no active session in store")
            TrainWorkoutDiagnostics.record("resumeWorkout noActiveSession")
            return
        }
        TrainWorkoutDiagnostics.record("resumeWorkout session=\(String(describing: session.persistentModelID))")
        presentWorkout(sessionID: session.persistentModelID)
    }

    func presentWorkout(sessionID: PersistentIdentifier) {
        presentedWorkoutSessionID = sessionID
        isViewingActiveWorkout = true
        AppLifecycleBroker.shared.isWorkoutOverlayPresented = true
        LiveWorkoutCoordinatorLaunchState.noteLiveWorkoutViewing(true)
        workoutSurfaceNeedsRefresh = false
        pendingTrainRoute = .activeWorkout(sessionID)
        TrainWorkoutDiagnostics.beginSession("presentWorkout")
        TrainWorkoutDiagnostics.record(
            "presentWorkout session=\(String(describing: sessionID))"
        )
    }

    func minimizeWorkout(source: String = "unknown") {
        dismissWorkoutOverlay(reason: "minimizeWorkout source=\(source)")
    }

    func noteWorkoutViewDisappearedWhilePresented(scenePhase: ScenePhase) {
        guard presentedWorkoutSessionID != nil else { return }
        TrainWorkoutDiagnostics.record(
            "workoutViewDisappearedWhilePresented scenePhase=\(scenePhase) trueBackground=\(AppLifecycleBroker.shared.resolvedIsInTrueBackground)"
        )
    }

    func markReadyForScenePhaseRefresh() {}

    func handleRootScenePhaseChange(from previousPhase: ScenePhase, to phase: ScenePhase) {
        lastRecordedScenePhase = phase
    }

    func requestWorkoutSurfaceRefresh(reason: String) {
        guard presentedWorkoutSessionID != nil else { return }
        bumpWorkoutSurfaceGeneration(reason: reason, previousPhase: lastRecordedScenePhase)
    }

    private func bumpWorkoutSurfaceGeneration(reason: String, previousPhase: ScenePhase) {
        workoutSurfaceNeedsRefresh = false
        workoutSurfaceGeneration += 1
        TrainWorkoutDiagnostics.record(
            "refreshWorkoutSurface reason=\(reason) prevPhase=\(previousPhase) gen=\(workoutSurfaceGeneration)"
        )
    }

    func syncWorkoutNavigationDismissed(source: String) {
        guard isViewingActiveWorkout else { return }
        dismissWorkoutOverlay(reason: "syncWorkoutNavigationDismissed source=\(source)")
    }

    func requestStripActiveWorkoutRoute() {
        stripActiveWorkoutRouteToken += 1
    }

    private func dismissWorkoutOverlay(reason: String) {
        presentedWorkoutSessionID = nil
        isViewingActiveWorkout = false
        pendingTrainRoute = nil
        AppLifecycleBroker.shared.isWorkoutOverlayPresented = false
        AppLifecycleBroker.shared.isLiveWorkoutSetFieldEditing = false
        LiveWorkoutCoordinatorLaunchState.noteLiveWorkoutViewing(false)
        workoutSurfaceNeedsRefresh = false
        requestStripActiveWorkoutRoute()
        trainNavigationResetToken += 1
        TrainWorkoutDiagnostics.record(reason)
    }

    func consumeCollapseWorkoutNavigationFlag() -> Bool {
        let shouldCollapse = collapseWorkoutNavigationOnNextTrainAppear
        collapseWorkoutNavigationOnNextTrainAppear = false
        return shouldCollapse
    }

    func requestScroll(to exerciseID: PersistentIdentifier) {
        scrollToExerciseID = exerciseID
    }

    func consumeScrollTarget() -> PersistentIdentifier? {
        let target = scrollToExerciseID
        scrollToExerciseID = nil
        return target
    }

    func makeStore() -> LiveWorkoutStore? {
        store
    }

    func resetTrainNavigation(reason: String) {
        dismissWorkoutOverlay(reason: "resetTrainNavigation \(reason)")
        pendingTrainRoute = nil
    }

    func hasStartedWatch(for sessionID: PersistentIdentifier) -> Bool {
        didStartWatchForSessionIDs.contains(sessionID)
    }

    func markWatchStarted(for sessionID: PersistentIdentifier) {
        didStartWatchForSessionIDs.insert(sessionID)
    }

    func clearWatchStarted(for sessionID: PersistentIdentifier) {
        didStartWatchForSessionIDs.remove(sessionID)
    }

    func publishHealthKitWriteNote(_ note: String?) {
        pendingHealthKitWriteNote = note
    }

    func consumeHealthKitWriteNote() -> String? {
        let note = pendingHealthKitWriteNote
        pendingHealthKitWriteNote = nil
        return note
    }

    func presentWellness(for session: WorkoutSession) {
        pendingWellnessSessionID = session.persistentModelID
        pendingWellnessMuscles = WorkoutMusclesWorked.muscles(for: session)
    }

    func dismissWellness() {
        pendingWellnessSessionID = nil
        pendingWellnessMuscles = []
    }
}
