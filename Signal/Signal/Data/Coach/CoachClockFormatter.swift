import Foundation

enum CoachClockFormatter: Sendable {
    nonisolated static func format(
        referenceDate: Date,
        calendar: Calendar = SchedulingCalendar.make()
    ) -> String {
        let dayKey = Summarizer.dayKey(for: referenceDate, calendar: calendar)
        let weekday = weekdayName(for: referenceDate, calendar: calendar)
        let time = formatTime(referenceDate, calendar: calendar)
        let timezoneID = calendar.timeZone.identifier
        return "Clock: \(dayKey) (\(weekday)) \(time) timezone \(timezoneID)"
    }

    nonisolated static func parseDayKey(_ dayKey: String, calendar: Calendar = SchedulingCalendar.make()) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    nonisolated static func calendarDaysBetween(
        earlierDayKey: String,
        laterDayKey: String,
        calendar: Calendar = SchedulingCalendar.make()
    ) -> Int? {
        guard let earlier = parseDayKey(earlierDayKey, calendar: calendar),
              let later = parseDayKey(laterDayKey, calendar: calendar)
        else { return nil }
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    private nonisolated static func weekdayName(for date: Date, calendar: Calendar) -> String {
        var englishCalendar = calendar
        englishCalendar.locale = Locale(identifier: "en_US_POSIX")
        let index = englishCalendar.component(.weekday, from: date) - 1
        guard englishCalendar.weekdaySymbols.indices.contains(index) else { return "Day" }
        return englishCalendar.weekdaySymbols[index]
    }

    private nonisolated static func formatTime(_ date: Date, calendar: Calendar) -> String {
        var englishCalendar = calendar
        englishCalendar.locale = Locale(identifier: "en_US_POSIX")
        let formatter = DateFormatter()
        formatter.calendar = englishCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
