import Foundation
import Observation

@MainActor
@Observable
final class TrainPreferences {
    static let shared = TrainPreferences()

    var suggestWarmupSets: Bool {
        didSet { persistSuggestWarmupSets() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.suggestWarmupSetsKey) == nil {
            suggestWarmupSets = true
        } else {
            suggestWarmupSets = defaults.bool(forKey: Self.suggestWarmupSetsKey)
        }
    }

    private func persistSuggestWarmupSets() {
        defaults.set(suggestWarmupSets, forKey: Self.suggestWarmupSetsKey)
    }

    private static let suggestWarmupSetsKey = "signal.train.suggestWarmupSets"
}
