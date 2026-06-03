import Foundation
import os
import Observation
import SwiftData

enum TrainRoute: Hashable {
    case activeWorkout(PersistentIdentifier)
    case history(PersistentIdentifier)
    case editRoutine(PersistentIdentifier?)
}

@MainActor
@Observable
final class LiveWorkoutCoordinator {
    var activeSession: WorkoutSession?
    var pendingTrainRoute: TrainRoute?
    var scrollToExerciseID: PersistentIdentifier?
    var collapseWorkoutNavigationOnNextTrainAppear = true
    var isViewingActiveWorkout = false
    var trainNavigationResetToken = 0
    var pendingHealthKitWriteNote: String?
    var pendingWellnessSessionID: PersistentIdentifier?
    var pendingWellnessMuscles: [Muscle] = []

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
        pendingTrainRoute = .activeWorkout(session.persistentModelID)
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

    func resetTrainNavigation() {
        isViewingActiveWorkout = false
        pendingTrainRoute = nil
        trainNavigationResetToken += 1
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
