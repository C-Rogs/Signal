import Foundation
import Observation

@MainActor
@Observable
final class TrainPreferences {
    static let shared = TrainPreferences()

    var suggestWarmupSets: Bool {
        didSet { persistSuggestWarmupSets() }
    }

    var hapticsEnabled: Bool {
        didSet { persistHapticsEnabled() }
    }

    var restBellEnabled: Bool {
        didSet { persistRestBellEnabled() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.suggestWarmupSetsKey) == nil {
            suggestWarmupSets = true
        } else {
            suggestWarmupSets = defaults.bool(forKey: Self.suggestWarmupSetsKey)
        }
        if defaults.object(forKey: Self.hapticsEnabledKey) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Self.hapticsEnabledKey)
        }
        if defaults.object(forKey: Self.restBellEnabledKey) == nil {
            restBellEnabled = true
        } else {
            restBellEnabled = defaults.bool(forKey: Self.restBellEnabledKey)
        }
    }

    private func persistSuggestWarmupSets() {
        defaults.set(suggestWarmupSets, forKey: Self.suggestWarmupSetsKey)
    }

    private func persistHapticsEnabled() {
        defaults.set(hapticsEnabled, forKey: Self.hapticsEnabledKey)
    }

    private func persistRestBellEnabled() {
        defaults.set(restBellEnabled, forKey: Self.restBellEnabledKey)
    }

    private static let suggestWarmupSetsKey = "signal.train.suggestWarmupSets"
    private static let hapticsEnabledKey = "signal.train.hapticsEnabled"
    private static let restBellEnabledKey = "signal.train.restBellEnabled"
}
