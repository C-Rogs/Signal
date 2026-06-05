import Foundation
import Testing
@testable import Signal

struct CoachClockFormatterTests {
  @Test func formatIncludesDayKeyWeekdayTimeAndTimezone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let reference = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 14, minute: 32))
    )

    let formatted = CoachClockFormatter.format(referenceDate: reference, calendar: calendar)
    var englishCalendar = calendar
    englishCalendar.locale = Locale(identifier: "en_US_POSIX")
    let weekdayIndex = englishCalendar.component(.weekday, from: reference) - 1
    let weekday = englishCalendar.weekdaySymbols[weekdayIndex]

    #expect(formatted.contains("Clock: 2026-06-05"))
    #expect(formatted.contains("(\(weekday))"))
    #expect(formatted.contains("14:32"))
    #expect(formatted.contains("timezone GMT"))
  }

  @Test func parseDayKeyRoundTrips() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parsed = CoachClockFormatter.parseDayKey("2026-06-05", calendar: calendar)
    #expect(parsed != nil)
    #expect(Summarizer.dayKey(for: parsed!, calendar: calendar) == "2026-06-05")
  }

  @Test func calendarDaysBetweenMeasuresGap() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let gap = CoachClockFormatter.calendarDaysBetween(
      earlierDayKey: "2026-06-01",
      laterDayKey: "2026-06-05",
      calendar: calendar
    )
    #expect(gap == 4)
  }
}
