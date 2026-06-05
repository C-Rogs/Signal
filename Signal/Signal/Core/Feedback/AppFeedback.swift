import Foundation
import Observation
import os

enum AppHapticEvent: Sendable {
    case tabChange
    case bannerTap
    case navigationPush
}

@MainActor
@Observable
final class AppFeedback {
    static let shared = AppFeedback(preferences: .shared)

    private let preferences: AppPreferences
    private let engine = HapticEngine()

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func play(_ event: AppHapticEvent) {
        guard preferences.hapticsEnabled else {
            Log.ui.debug("app haptic skipped event=\(String(describing: event), privacy: .public)")
            return
        }
        engine.playApp(event)
    }
}
