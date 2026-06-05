import Foundation
import Observation

@MainActor
@Observable
final class CoachPreferences {
    static let shared = CoachPreferences()

    var smartContextEnabled: Bool {
        didSet { persistSmartContext() }
    }

    var deepReasoningEnabled: Bool {
        didSet { persistDeepReasoning() }
    }

    var compoundQueriesEnabled: Bool {
        didSet { persistCompoundQueries() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let flags = CoachFeatureFlags.current(defaults: defaults)
        smartContextEnabled = flags.smartContextEnabled
        deepReasoningEnabled = flags.deepReasoningEnabled
        compoundQueriesEnabled = flags.compoundQueriesEnabled
    }

    var featureFlags: CoachFeatureFlags {
        CoachFeatureFlags(
            smartContextEnabled: smartContextEnabled,
            deepReasoningEnabled: deepReasoningEnabled,
            compoundQueriesEnabled: compoundQueriesEnabled
        )
    }

    private func persistSmartContext() {
        defaults.set(smartContextEnabled, forKey: CoachPreferenceKeys.smartContext)
    }

    private func persistDeepReasoning() {
        defaults.set(deepReasoningEnabled, forKey: CoachPreferenceKeys.deepReasoning)
    }

    private func persistCompoundQueries() {
        defaults.set(compoundQueriesEnabled, forKey: CoachPreferenceKeys.compoundQueries)
    }
}
