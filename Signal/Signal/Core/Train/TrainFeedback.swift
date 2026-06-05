import Foundation
import Observation
import os

enum TrainHapticEvent: Sendable {
    case setComplete
    case prCelebration
    case restStart
    case restEnd
    case restCountdown(second: Int)
    case restMilestone(second: Int)
    case workoutStart
    case workoutFinish
    case wellnessComplete
    case primaryTap
    case fillPrevious
    case rpeSelect
    case timerExtend
    case timerShrink
    case warmupAdded
    case warning
    case selection
}

@MainActor
@Observable
final class TrainFeedback {
    static let shared = TrainFeedback(preferences: .shared)

    private let preferences: TrainPreferences
    private let engine = HapticEngine()
    private let bell = RestBellPlayer()

    init(preferences: TrainPreferences) {
        self.preferences = preferences
    }

    func play(_ event: TrainHapticEvent) {
        guard preferences.hapticsEnabled else {
            Log.workout.debug("train haptic skipped event=\(String(describing: event), privacy: .public)")
            return
        }
        engine.playTrain(event)
    }

    func playRestBell() {
        guard preferences.restBellEnabled else {
            Log.workout.debug("rest bell skipped preference off")
            return
        }
        bell.play()
    }
}
