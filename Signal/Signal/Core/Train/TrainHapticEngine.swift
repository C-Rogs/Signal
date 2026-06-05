import os
import UIKit

@MainActor
final class TrainHapticEngine {
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    func play(_ event: TrainHapticEvent) {
        switch event {
        case .setComplete:
            notification.prepare()
            notification.notificationOccurred(.success)
        case .prCelebration:
            notification.prepare()
            notification.notificationOccurred(.success)
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                heavyImpact.prepare()
                heavyImpact.impactOccurred()
            }
        case .restStart:
            lightImpact.prepare()
            lightImpact.impactOccurred()
        case .restEnd:
            notification.prepare()
            notification.notificationOccurred(.success)
        case .restCountdown:
            lightImpact.prepare()
            lightImpact.impactOccurred()
        case .workoutFinish:
            notification.prepare()
            notification.notificationOccurred(.success)
        case .primaryTap:
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
        case .warning:
            notification.prepare()
            notification.notificationOccurred(.warning)
        case .selection:
            selection.prepare()
            selection.selectionChanged()
        }
        Log.workout.debug("train haptic event=\(String(describing: event), privacy: .public)")
    }

    func playCountdown(second: Int) {
        if second == 1 {
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
        } else {
            lightImpact.prepare()
            lightImpact.impactOccurred()
        }
        Log.workout.debug("train haptic countdown second=\(second, privacy: .public)")
    }
}
