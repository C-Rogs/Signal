import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    var hapticsEnabled: Bool {
        didSet { persistHapticsEnabled() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.hapticsEnabledKey) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Self.hapticsEnabledKey)
        }
    }

    private func persistHapticsEnabled() {
        defaults.set(hapticsEnabled, forKey: Self.hapticsEnabledKey)
    }

    private static let hapticsEnabledKey = "signal.app.hapticsEnabled"
}
