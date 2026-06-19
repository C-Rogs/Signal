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
    var trainNavigationResetToken = 0
    var stripActiveWorkoutRouteToken = 0
    var pendingHealthKitWriteNote: String?
    var pendingWellnessSessionID: PersistentIdentifier?
    var pendingWellnessMuscles: [Muscle] = []

    @ObservationIgnored private var lastRecordedScenePhase: ScenePhase = .active
    @ObservationIgnored private var isReadyForScenePhaseRefresh = false

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
        TrainApplicationLifecycle.isLiveWorkoutSessionInProgress = activeSession != nil
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
        TrainApplicationLifecycle.isWorkoutOverlayPresented = true
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
        workoutSurfaceNeedsRefresh = true
        TrainWorkoutDiagnostics.record(
            "workoutViewDisappearedWhilePresented scenePhase=\(scenePhase) trueBackground=\(TrainApplicationLifecycle.resolvedIsInTrueBackground) needsRefresh=true"
        )
    }

    func markReadyForScenePhaseRefresh() {
        isReadyForScenePhaseRefresh = true
    }

    func handleRootScenePhaseChange(from previousPhase: ScenePhase, to phase: ScenePhase) {
        if phase == .active, previousPhase == .background {
            refreshWorkoutSurfaceAfterSceneActivation(from: previousPhase)
        }
        lastRecordedScenePhase = phase
    }

    func requestWorkoutSurfaceRefresh(reason: String) {
        guard presentedWorkoutSessionID != nil else { return }
        bumpWorkoutSurfaceGeneration(reason: reason, previousPhase: lastRecordedScenePhase)
    }

    private func refreshWorkoutSurfaceAfterSceneActivation(from previousPhase: ScenePhase) {
        guard presentedWorkoutSessionID != nil else { return }

        guard workoutSurfaceNeedsRefresh else { return }
        bumpWorkoutSurfaceGeneration(reason: "disappear", previousPhase: previousPhase)
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
        TrainApplicationLifecycle.isWorkoutOverlayPresented = false
        TrainApplicationLifecycle.isLiveWorkoutSetFieldEditing = false
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
