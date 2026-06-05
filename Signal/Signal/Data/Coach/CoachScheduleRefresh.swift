import Foundation

enum CoachScheduleRefresh {
    static func freshSummary() async -> String? {
        let summary = await CalendarContextBuilder().buildSummary()
        guard let summary, !summary.isEmpty else { return nil }
        return summary
    }
}
