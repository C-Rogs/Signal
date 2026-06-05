import Foundation
import Observation
import os

enum TrainHapticEvent: Sendable {
    case setComplete
    case prCelebration
    case restStart
    case restEnd
    case restCountdown
    case workoutFinish
    case primaryTap
    case warning
    case selection
}

@MainActor
@Observable
final class TrainFeedback {
    static let shared = TrainFeedback(preferences: .shared)

    private let preferences: TrainPreferences
    private let haptics: TrainHapticEngine
    private let bell: RestBellPlayer

    init(preferences: TrainPreferences) {
        self.preferences = preferences
        self.haptics = TrainHapticEngine()
        self.bell = RestBellPlayer()
    }

    func play(_ event: TrainHapticEvent) {
        guard preferences.hapticsEnabled else {
            Log.workout.debug("train haptic skipped event=\(String(describing: event), privacy: .public)")
            return
        }
        haptics.play(event)
    }

    func playRestCountdown(second: Int) {
        guard preferences.hapticsEnabled else { return }
        haptics.playCountdown(second: second)
    }

    func playRestBell() {
        guard preferences.restBellEnabled else {
            Log.workout.debug("rest bell skipped preference off")
            return
        }
        bell.play()
    }
}
