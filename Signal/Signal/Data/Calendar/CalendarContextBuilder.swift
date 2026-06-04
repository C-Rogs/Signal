import Foundation
import os

struct CalendarEventSnapshot: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum CalendarLookahead {
    static let daysAfterToday = 7

    static func window(referenceDate: Date, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        guard let endExclusive = calendar.date(byAdding: .day, value: daysAfterToday + 1, to: startOfToday) else {
            return DateInterval(start: startOfToday, duration: 0)
        }
        return DateInterval(start: startOfToday, end: endExclusive)
    }
}

enum CalendarBusyDayPolicy {
    static let totalEventThreshold = 4
    static let meetingsBeforeCutoffHour = 17
    static let meetingsBeforeCutoffThreshold = 3

    static func isBusyDay(
        eventsOnDay: [CalendarEventSnapshot],
        calendar: Calendar,
        dayStart: Date
    ) -> Bool {
        if eventsOnDay.count >= totalEventThreshold {
            return true
        }
        let timed = eventsOnDay.filter { !$0.isAllDay }
        let cutoff = calendar.date(
            bySettingHour: meetingsBeforeCutoffHour,
            minute: 0,
            second: 0,
            of: dayStart
        ) ?? dayStart
        let beforeCutoff = timed.filter { $0.startDate < cutoff }.count
        return beforeCutoff >= meetingsBeforeCutoffThreshold
    }
}

enum CalendarEventFilter {
    static func events(
        in window: DateInterval,
        from all: [CalendarEventSnapshot]
    ) -> [CalendarEventSnapshot] {
        all
            .filter { $0.endDate > window.start && $0.startDate < window.end }
            .sorted { $0.startDate < $1.startDate }
    }

    static func events(
        on dayStart: Date,
        calendar: Calendar,
        from all: [CalendarEventSnapshot]
    ) -> [CalendarEventSnapshot] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        return all.filter { $0.endDate > dayStart && $0.startDate < dayEnd }
    }

    static func timedMeetingsBeforeCutoff(
        on dayStart: Date,
        calendar: Calendar,
        from eventsOnDay: [CalendarEventSnapshot]
    ) -> Int {
        let cutoff = calendar.date(
            bySettingHour: CalendarBusyDayPolicy.meetingsBeforeCutoffHour,
            minute: 0,
            second: 0,
            of: dayStart
        ) ?? dayStart
        return eventsOnDay.filter { !$0.isAllDay && $0.startDate < cutoff }.count
    }
}

enum CalendarSummaryFormatter {
    static func assembleSummary(
        events: [CalendarEventSnapshot],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let window = CalendarLookahead.window(referenceDate: referenceDate, calendar: calendar)
        let filtered = CalendarEventFilter.events(in: window, from: events)

        if filtered.isEmpty {
            return "No calendar events in the next \(CalendarLookahead.daysAfterToday + 1) days."
        }

        var dayStart = window.start
        var parts: [String] = []

        while dayStart < window.end {
            let dayEvents = CalendarEventFilter.events(on: dayStart, calendar: calendar, from: filtered)
            if !dayEvents.isEmpty {
                parts.append(dayLine(
                    dayStart: dayStart,
                    dayEvents: dayEvents,
                    referenceDate: referenceDate,
                    calendar: calendar
                ))
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = nextDay
        }

        return parts.joined(separator: ". ") + "."
    }

    static func busyDayChipTitle(
        events: [CalendarEventSnapshot],
        referenceDate: Date,
        calendar: Calendar
    ) -> String? {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let todayEvents = CalendarEventFilter.events(on: startOfToday, calendar: calendar, from: events)
        let isBusy = CalendarBusyDayPolicy.isBusyDay(
            eventsOnDay: todayEvents,
            calendar: calendar,
            dayStart: startOfToday
        )
        return isBusy ? "Busy day" : nil
    }

    private static func dayLine(
        dayStart: Date,
        dayEvents: [CalendarEventSnapshot],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let beforeCutoff = CalendarEventFilter.timedMeetingsBeforeCutoff(
            on: dayStart,
            calendar: calendar,
            from: dayEvents
        )
        let busy = CalendarBusyDayPolicy.isBusyDay(
            eventsOnDay: dayEvents,
            calendar: calendar,
            dayStart: dayStart
        )

        let core: String
        if calendar.isDate(dayStart, inSameDayAs: referenceDate) {
            if beforeCutoff > 0 {
                core = "Today: \(dayEvents.count) events, \(beforeCutoff) before 5pm"
            } else {
                core = "Today: \(dayEvents.count) events"
            }
        } else {
            let weekday = weekdayName(for: dayStart, calendar: calendar)
            if beforeCutoff >= CalendarBusyDayPolicy.meetingsBeforeCutoffThreshold {
                core = "\(weekday): \(beforeCutoff) meetings before 5pm"
            } else if beforeCutoff > 0 {
                core = "\(weekday): \(beforeCutoff) meetings before 5pm"
            } else {
                core = "\(weekday): \(dayEvents.count) events"
            }
        }

        return busy ? "\(core) (busy)" : core
    }

    private static func weekdayName(for date: Date, calendar: Calendar) -> String {
        var englishCalendar = calendar
        englishCalendar.locale = Locale(identifier: "en_US_POSIX")
        let index = englishCalendar.component(.weekday, from: date) - 1
        guard englishCalendar.weekdaySymbols.indices.contains(index) else { return "Day" }
        return englishCalendar.weekdaySymbols[index]
    }
}

actor CalendarContextBuilder {
    private let store: CalendarEventStore

    init(store: CalendarEventStore = .shared) {
        self.store = store
    }

    func buildSummary(
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async -> String? {
        let access = await store.currentAccessState()
        guard case .authorized = access else {
            Log.calendar.info(
                "calendar summary skipped access=\(String(describing: access), privacy: .public)"
            )
            return nil
        }

        let window = CalendarLookahead.window(referenceDate: referenceDate, calendar: calendar)
        let events = await store.fetchEvents(in: window)
        let summary = CalendarSummaryFormatter.assembleSummary(
            events: events,
            referenceDate: referenceDate,
            calendar: calendar
        )
        Log.calendar.info(
            "calendar summary built events=\(events.count, privacy: .public) chars=\(summary.count, privacy: .public)"
        )
        return summary
    }

    func todayBusyChipTitle(
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async -> String? {
        guard case .authorized = await store.currentAccessState() else { return nil }

        let window = CalendarLookahead.window(referenceDate: referenceDate, calendar: calendar)
        let events = await store.fetchEvents(in: window)
        let title = CalendarSummaryFormatter.busyDayChipTitle(
            events: events,
            referenceDate: referenceDate,
            calendar: calendar
        )
        if title != nil {
            Log.calendar.info("busy day chip shown for today")
        }
        return title
    }
}
