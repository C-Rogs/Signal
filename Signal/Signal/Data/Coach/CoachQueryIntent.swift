import Foundation

enum CoachQueryIntent {
    nonisolated static func isScheduleFocused(_ query: String) -> Bool {
        CoachQueryRouter.classify(query) == .schedule
    }

    nonisolated static func isExerciseHistoryFocused(_ query: String) -> Bool {
        CoachQueryRouter.classify(query) == .exerciseHistory
    }

    nonisolated static func isVolumeFocused(_ query: String) -> Bool {
        containsAny(in: query, keywords: [
            "volume",
            "sets per",
            "working sets",
            "muscle group",
            "chest",
            "back",
            "legs",
            "shoulders",
            "arms",
            "hypertrophy",
            "undertrained",
            "overtrained",
        ])
    }

    nonisolated static func isOffTopic(_ query: String) -> Bool {
        containsAny(in: query, keywords: [
            "election",
            "president",
            "stock",
            "bitcoin",
            "weather forecast",
            "write me a poem",
            "recipe for",
        ])
    }

    nonisolated static func isClinical(_ query: String) -> Bool {
        containsAny(in: query, keywords: [
            "diagnose",
            "diagnosis",
            "injury",
            "fracture",
            "torn",
            "arthritis",
            "doctor said",
            "pain in my",
            "hurt my",
        ])
    }

    private nonisolated static func containsAny(in query: String, keywords: [String]) -> Bool {
        let normalized = query.lowercased()
        return keywords.contains { normalized.contains($0) }
    }
}
