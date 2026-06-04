import Foundation

enum CoachQueryIntent {
    nonisolated static func isScheduleFocused(_ query: String) -> Bool {
        let normalized = query.lowercased()
        let keywords = [
            "calendar",
            "schedule",
            "meeting",
            "meetings",
            "busy day",
            "tomorrow",
            "today",
            "this week",
            "next week",
        ]
        return keywords.contains { normalized.contains($0) }
    }
}
