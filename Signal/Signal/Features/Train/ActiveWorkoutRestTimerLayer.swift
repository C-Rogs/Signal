import Combine
import os
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ActiveWorkoutRestTimerCoordinator {
    private(set) var dynamicRestNotice: String?
    private(set) var showsRestBar = false
    private var dynamicRestState = DynamicRestState()
    private var restFeedbackState = RestTimerFeedbackState()
    private var tick = Date()

    func acknowledgeRestTimerStarted(_ exercise: WorkoutExercise) {
        let exerciseID = RestTimerFeedbackEvaluator.exerciseID(for: exercise)
        restFeedbackState.acknowledgeRestStarted(exerciseID: exerciseID)
        TrainFeedback.shared.play(.restStart)
    }

    func markUserSkippedFeedback() {
        restFeedbackState.markUserSkipped()
    }

    func activeRestTimer(in exercises: [WorkoutExercise]) -> (exercise: WorkoutExercise, remaining: Int)? {
        _ = tick
        let now = Date()
        var best: (WorkoutExercise, Date)?
        for exercise in exercises {
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

    func handleTick(
        at date: Date,
        exercises: [WorkoutExercise],
        watchBridge: LiveWorkoutWatchBridge,
        store: LiveWorkoutStore,
        onCoordinatorRefresh: () -> Void
    ) {
        tick = date
        applyDynamicRestExtension(
            at: date,
            exercises: exercises,
            watchBridge: watchBridge,
            store: store,
            onCoordinatorRefresh: onCoordinatorRefresh
        )
        handleRestTimerFeedback(
            exercises: exercises,
            store: store,
            onCoordinatorRefresh: onCoordinatorRefresh
        )
        showsRestBar = activeRestTimer(in: exercises) != nil
    }

    func stopRest(
        for exercise: WorkoutExercise,
        store: LiveWorkoutStore,
        onCoordinatorRefresh: () -> Void
    ) {
        restFeedbackState.markUserSkipped()
        TrainFeedback.shared.play(.primaryTap)
        try? store.stopRestTimer(for: exercise)
        onCoordinatorRefresh()
    }

    func adjustRest(
        for exercise: WorkoutExercise,
        by seconds: Int,
        store: LiveWorkoutStore,
        onCoordinatorRefresh: () -> Void
    ) {
        if seconds > 0 {
            TrainFeedback.shared.play(.timerExtend)
        } else {
            TrainFeedback.shared.play(.timerShrink)
        }
        try? store.adjustRestTimer(for: exercise, by: seconds)
        onCoordinatorRefresh()
    }

    private func handleRestTimerFeedback(
        exercises: [WorkoutExercise],
        store: LiveWorkoutStore,
        onCoordinatorRefresh: () -> Void
    ) {
        let active = activeRestTimer(in: exercises)
        let endedExerciseID = restFeedbackState.trackedExerciseID
        let activeID = active.map { RestTimerFeedbackEvaluator.exerciseID(for: $0.exercise) }
        let actions = restFeedbackState.advance(
            activeExerciseID: activeID,
            remainingSeconds: active?.remaining
        )
        for action in actions {
            switch action {
            case .restStarted:
                TrainFeedback.shared.play(.restStart)
            case .countdown(let second):
                TrainFeedback.shared.play(.restCountdown(second: second))
            case .milestone(let second):
                TrainFeedback.shared.play(.restMilestone(second: second))
            case .restEnded:
                TrainFeedback.shared.play(.restEnd)
                TrainFeedback.shared.playRestBell()
                if let endedExerciseID,
                   let exercise = exercises.first(where: {
                       RestTimerFeedbackEvaluator.exerciseID(for: $0) == endedExerciseID
                   }) {
                    try? store.stopRestTimer(for: exercise)
                    onCoordinatorRefresh()
                }
            }
        }
    }

    private func applyDynamicRestExtension(
        at now: Date,
        exercises: [WorkoutExercise],
        watchBridge: LiveWorkoutWatchBridge,
        store: LiveWorkoutStore,
        onCoordinatorRefresh: () -> Void
    ) {
        guard let activeRest = activeRestTimer(in: exercises),
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

        let priorExtensionCount = dynamicRestState.extensionCount
        dynamicRestState = decision.newState
        dynamicRestNotice = decision.notice
        do {
            try store.adjustRestTimer(for: activeRest.exercise, by: decision.extensionSeconds)
            if decision.newState.extensionCount > priorExtensionCount {
                TrainFeedback.shared.play(.warning)
            }
            onCoordinatorRefresh()
            Log.workout.debug(
                "dynamic rest extended seconds=\(decision.extensionSeconds, privacy: .public) bpm=\(watchBridge.latestHeartRateBPM ?? 0, privacy: .public) extensions=\(decision.newState.extensionCount, privacy: .public)"
            )
        } catch {
            Log.workout.error(
                "dynamic rest extend failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

struct ActiveWorkoutRestTimerLayer: View {
    @Bindable var coordinator: ActiveWorkoutRestTimerCoordinator
    let exercises: [WorkoutExercise]
    let scenePhase: ScenePhase
    let watchBridge: LiveWorkoutWatchBridge
    let store: LiveWorkoutStore
    let onCoordinatorRefresh: () -> Void

    var body: some View {
        Group {
            if scenePhase == .active, let activeRest = coordinator.activeRestTimer(in: exercises) {
                FloatingRestTimerBar(
                    exerciseTitle: activeRest.exercise.exerciseTitle,
                    remainingSeconds: activeRest.remaining,
                    autoregulationNotice: coordinator.dynamicRestNotice,
                    onSkip: {
                        coordinator.stopRest(
                            for: activeRest.exercise,
                            store: store,
                            onCoordinatorRefresh: onCoordinatorRefresh
                        )
                    },
                    onSubtract15: {
                        coordinator.adjustRest(
                            for: activeRest.exercise,
                            by: -15,
                            store: store,
                            onCoordinatorRefresh: onCoordinatorRefresh
                        )
                    },
                    onAdd15: {
                        coordinator.adjustRest(
                            for: activeRest.exercise,
                            by: 15,
                            store: store,
                            onCoordinatorRefresh: onCoordinatorRefresh
                        )
                    }
                )
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                    coordinator.handleTick(
                        at: date,
                        exercises: exercises,
                        watchBridge: watchBridge,
                        store: store,
                        onCoordinatorRefresh: onCoordinatorRefresh
                    )
                }
            }
        }
    }
}
