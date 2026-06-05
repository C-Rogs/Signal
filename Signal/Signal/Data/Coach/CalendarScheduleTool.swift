import Foundation
import FoundationModels

struct CalendarScheduleTool: Tool {
    let name = "calendarSchedule"
    let description = "Calendar events from fromDayKey through toDayKey inclusive."

    @Generable
    struct Arguments {
        @Guide(description: "Start day YYYY-MM-DD")
        var fromDayKey: String

        @Guide(description: "End day YYYY-MM-DD inclusive")
        var toDayKey: String
    }

    func call(arguments: Arguments) async throws -> String {
        let calendar = SchedulingCalendar.make()
        guard let fromDate = CoachClockFormatter.parseDayKey(arguments.fromDayKey, calendar: calendar),
              let toDate = CoachClockFormatter.parseDayKey(arguments.toDayKey, calendar: calendar)
        else {
            return "Invalid dayKey. Use YYYY-MM-DD for fromDayKey and toDayKey."
        }

        let fromStart = calendar.startOfDay(for: fromDate)
        let toStart = calendar.startOfDay(for: toDate)
        guard fromStart <= toStart else {
            return "fromDayKey must be on or before toDayKey."
        }
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: toStart) else {
            return "Could not build date range."
        }

        let window = DateInterval(start: fromStart, end: endExclusive)
        _ = await CalendarEventStore.shared.requestAccessIfNeeded()
        let access = await CalendarEventStore.shared.currentAccessState()
        guard case .authorized = access else {
            return "Calendar access unavailable or no events scheduled."
        }

        let events = await CalendarEventStore.shared.fetchEvents(in: window)
        return CalendarSummaryFormatter.assembleSummary(
            events: events,
            window: window,
            referenceDate: Date(),
            calendar: calendar
        )
    }
}
