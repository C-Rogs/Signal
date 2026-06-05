import Foundation

enum CalendarDisruptorLookback {
    static func eveningStartDay(referenceDate: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    static func window(referenceDate: Date, calendar: Calendar) -> DateInterval {
        let yesterday = eveningStartDay(referenceDate: referenceDate, calendar: calendar)
        let windowStart = calendar.date(
            bySettingHour: CalendarDisruptorHeuristics.eveningWindowStartHour,
            minute: 0,
            second: 0,
            of: yesterday
        ) ?? yesterday
        let today = calendar.startOfDay(for: referenceDate)
        let windowEnd = calendar.date(
            bySettingHour: CalendarDisruptorHeuristics.morningWindowEndHour,
            minute: 0,
            second: 0,
            of: today
        ) ?? today
        return DateInterval(start: windowStart, end: windowEnd)
    }
}
