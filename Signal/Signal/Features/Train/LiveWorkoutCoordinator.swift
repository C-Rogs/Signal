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
    }

    func resumeWorkout() {
        refresh()
        guard let session = activeSession else {
            Log.workout.info("resume requested but no active session in store")
            return
        }
        presentWorkout(sessionID: session.persistentModelID)
    }

    func presentWorkout(sessionID: PersistentIdentifier) {
        presentedWorkoutSessionID = sessionID
        isViewingActiveWorkout = true
        pendingTrainRoute = nil
        workoutSurfaceNeedsRefresh = false
        workoutSurfaceGeneration += 1
        requestStripActiveWorkoutRoute()
        TrainWorkoutDiagnostics.record(
            "presentWorkout session=\(String(describing: sessionID)) gen=\(workoutSurfaceGeneration)"
        )
    }

    func minimizeWorkout() {
        dismissWorkoutOverlay(reason: "minimizeWorkout")
    }

    func noteWorkoutViewDisappearedWhilePresented(scenePhase: ScenePhase) {
        guard presentedWorkoutSessionID != nil else { return }
        workoutSurfaceNeedsRefresh = true
        TrainWorkoutDiagnostics.record(
            "workoutViewDisappearedWhilePresented scenePhase=\(scenePhase) needsRefresh=true"
        )
    }

    func markReadyForScenePhaseRefresh() {
        isReadyForScenePhaseRefresh = true
    }

    func handleRootScenePhaseChange(to phase: ScenePhase) {
        let previous = lastRecordedScenePhase
        lastRecordedScenePhase = phase
        guard isReadyForScenePhaseRefresh else { return }
        guard phase == .active else { return }
        refreshWorkoutSurfaceAfterSceneActivation(from: previous)
    }

    func requestWorkoutSurfaceRefresh(reason: String) {
        guard presentedWorkoutSessionID != nil else { return }
        bumpWorkoutSurfaceGeneration(reason: reason, previousPhase: lastRecordedScenePhase)
    }

    private func refreshWorkoutSurfaceAfterSceneActivation(from previousPhase: ScenePhase) {
        guard presentedWorkoutSessionID != nil else { return }

        let reason: String?
        if workoutSurfaceNeedsRefresh {
            reason = "disappear"
        } else if previousPhase == .inactive {
            reason = "inactiveReturn"
        } else if previousPhase == .background {
            reason = "backgroundReturn"
        } else {
            reason = nil
        }

        guard let reason else { return }
        bumpWorkoutSurfaceGeneration(reason: reason, previousPhase: previousPhase)
    }

    private func bumpWorkoutSurfaceGeneration(reason: String, previousPhase: ScenePhase) {
        workoutSurfaceNeedsRefresh = false
        workoutSurfaceGeneration += 1
        TrainWorkoutDiagnostics.record(
            "refreshWorkoutSurface reason=\(reason) prevPhase=\(previousPhase) gen=\(workoutSurfaceGeneration)"
        )
    }

    func requestStripActiveWorkoutRoute() {
        stripActiveWorkoutRouteToken += 1
    }

    private func dismissWorkoutOverlay(reason: String) {
        presentedWorkoutSessionID = nil
        isViewingActiveWorkout = false
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
