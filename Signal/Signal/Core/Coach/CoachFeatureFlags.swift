import Foundation

enum CoachPreferenceKeys {
    nonisolated static let smartContext = "signal.coach.smartContextEnabled"
    nonisolated static let deepReasoning = "signal.coach.deepReasoningEnabled"
    nonisolated static let compoundQueries = "signal.coach.compoundQueriesEnabled"
    nonisolated static let conversationMemory = "signal.coach.conversationMemoryEnabled"
}

struct CoachFeatureFlags: Sendable, Equatable {
    var smartContextEnabled: Bool
    var deepReasoningEnabled: Bool
    var compoundQueriesEnabled: Bool
    var conversationMemoryEnabled: Bool

    static let defaults = CoachFeatureFlags(
        smartContextEnabled: true,
        deepReasoningEnabled: true,
        compoundQueriesEnabled: true,
        conversationMemoryEnabled: true
    )

    nonisolated static func current(defaults userDefaults: UserDefaults = .standard) -> CoachFeatureFlags {
        CoachFeatureFlags(
            smartContextEnabled: boolValue(forKey: CoachPreferenceKeys.smartContext, default: true, defaults: userDefaults),
            deepReasoningEnabled: boolValue(forKey: CoachPreferenceKeys.deepReasoning, default: true, defaults: userDefaults),
            compoundQueriesEnabled: boolValue(
                forKey: CoachPreferenceKeys.compoundQueries,
                default: true,
                defaults: userDefaults
            ),
            conversationMemoryEnabled: boolValue(
                forKey: CoachPreferenceKeys.conversationMemory,
                default: true,
                defaults: userDefaults
            )
        )
    }

    nonisolated private static func boolValue(
        forKey key: String,
        default defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
