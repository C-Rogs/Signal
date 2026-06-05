import os
import UIKit

@MainActor
final class HapticEngine {
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)

    func playApp(_ event: AppHapticEvent) {
        switch event {
        case .tabChange:
            selection.prepare()
            selection.selectionChanged()
        case .bannerTap:
            lightImpact.prepare()
            lightImpact.impactOccurred()
        case .navigationPush:
            softImpact.prepare()
            softImpact.impactOccurred(intensity: 0.55)
        }
        Log.ui.debug("app haptic event=\(String(describing: event), privacy: .public)")
    }

    func playTrain(_ event: TrainHapticEvent) {
        switch event {
        case .setComplete:
            notification.prepare()
            notification.notificationOccurred(.success)
        case .prCelebration:
            notification.prepare()
            notification.notificationOccurred(.success)
            delayed(80) { [self] in
                heavyImpact.prepare()
                heavyImpact.impactOccurred(intensity: 1)
            }
        case .restStart:
            softImpact.prepare()
            softImpact.impactOccurred(intensity: 0.7)
            delayed(55) { [self] in
                lightImpact.prepare()
                lightImpact.impactOccurred(intensity: 0.5)
            }
        case .restEnd:
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
            delayed(90) { [self] in
                notification.prepare()
                notification.notificationOccurred(.success)
            }
        case .restCountdown(let second):
            playRestCountdown(second: second)
        case .restMilestone(let second):
            playRestMilestone(second: second)
        case .workoutStart:
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
            delayed(70) { [self] in
                lightImpact.prepare()
                lightImpact.impactOccurred()
            }
        case .workoutFinish:
            playSessionCompleteCelebration()
        case .wellnessComplete:
            playWellnessCelebration()
        case .primaryTap:
            mediumImpact.prepare()
            mediumImpact.impactOccurred(intensity: 0.85)
        case .fillPrevious:
            selection.prepare()
            selection.selectionChanged()
            delayed(45) { [self] in
                lightImpact.prepare()
                lightImpact.impactOccurred(intensity: 0.6)
            }
        case .rpeSelect:
            selection.prepare()
            selection.selectionChanged()
        case .timerExtend:
            lightImpact.prepare()
            lightImpact.impactOccurred()
            delayed(65) { [self] in
                mediumImpact.prepare()
                mediumImpact.impactOccurred(intensity: 0.75)
            }
        case .timerShrink:
            softImpact.prepare()
            softImpact.impactOccurred(intensity: 0.65)
        case .warmupAdded:
            notification.prepare()
            notification.notificationOccurred(.success)
        case .warning:
            notification.prepare()
            notification.notificationOccurred(.warning)
        case .selection:
            selection.prepare()
            selection.selectionChanged()
        }
        Log.workout.debug("train haptic event=\(String(describing: event), privacy: .public)")
    }

    private func playRestCountdown(second: Int) {
        switch second {
        case 0:
            heavyImpact.prepare()
            heavyImpact.impactOccurred()
        case 1:
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
        default:
            lightImpact.prepare()
            lightImpact.impactOccurred(intensity: 0.7)
        }
        Log.workout.debug("train haptic countdown second=\(second, privacy: .public)")
    }

    private func playRestMilestone(second: Int) {
        switch second {
        case 30:
            softImpact.prepare()
            softImpact.impactOccurred(intensity: 0.45)
        case 10:
            lightImpact.prepare()
            lightImpact.impactOccurred(intensity: 0.55)
            delayed(40) { [self] in
                lightImpact.prepare()
                lightImpact.impactOccurred(intensity: 0.4)
            }
        default:
            lightImpact.prepare()
            lightImpact.impactOccurred(intensity: 0.5)
        }
        Log.workout.debug("train haptic milestone second=\(second, privacy: .public)")
    }

    private func playWellnessCelebration() {
        notification.prepare()
        notification.notificationOccurred(.success)
        delayed(100) { [self] in
            lightImpact.prepare()
            lightImpact.impactOccurred()
            delayed(80) { [self] in
                mediumImpact.prepare()
                mediumImpact.impactOccurred(intensity: 0.8)
            }
        }
    }

    private func playSessionCompleteCelebration() {
        notification.prepare()
        notification.notificationOccurred(.success)
        delayed(90) { [self] in
            lightImpact.prepare()
            lightImpact.impactOccurred()
            delayed(70) { [self] in
                mediumImpact.prepare()
                mediumImpact.impactOccurred()
                delayed(70) { [self] in
                    heavyImpact.prepare()
                    heavyImpact.impactOccurred()
                    delayed(110) { [self] in
                        notification.prepare()
                        notification.notificationOccurred(.success)
                    }
                }
            }
        }
    }

    private func delayed(_ milliseconds: Int, action: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            action()
        }
    }
}
