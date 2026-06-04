import Foundation
import FoundationModels

struct CalendarScheduleTool: Tool {
    let name = "calendarSchedule"
    let description = "On-device calendar for today and the next 7 days (event titles and times only)."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        _ = await CalendarEventStore.shared.requestAccessIfNeeded()
        let builder = CalendarContextBuilder()
        if let summary = await builder.buildSummary() {
            return summary
        }
        return "Calendar access unavailable or no events scheduled."
    }
}
