import XCTest
@testable import Signal

final class CalendarContextBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private func referenceDate() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9))!
    }

    private func event(
        on reference: Date,
        dayOffset: Int,
        hour: Int,
        minute: Int = 0,
        durationMinutes: Int = 60,
        title: String = "Meeting",
        isAllDay: Bool = false
    ) -> CalendarEventSnapshot {
        let dayStart = calendar.startOfDay(for: reference)
        let startDay = calendar.date(byAdding: .day, value: dayOffset, to: dayStart)!
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startDay)!
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return CalendarEventSnapshot(
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay
        )
    }

    private func event(
        title: String,
        dayOffset: Int,
        hour: Int,
        minute: Int = 0,
        durationMinutes: Int = 60,
        isAllDay: Bool = false
    ) -> CalendarEventSnapshot {
        event(
            on: referenceDate(),
            dayOffset: dayOffset,
            hour: hour,
            minute: minute,
            durationMinutes: durationMinutes,
            title: title,
            isAllDay: isAllDay
        )
    }

    // MARK: - Window filtering

    func testWindowIncludesTodayPlusSevenDays() {
        let window = CalendarLookahead.window(referenceDate: referenceDate(), calendar: calendar)
        let expectedEnd = calendar.date(byAdding: .day, value: 8, to: window.start)!
        XCTAssertEqual(window.start, calendar.startOfDay(for: referenceDate()))
        XCTAssertEqual(window.end, expectedEnd)
    }

    func testEventFilterKeepsOverlappingEventsOnly() {
        let window = CalendarLookahead.window(referenceDate: referenceDate(), calendar: calendar)
        let inside = event(title: "Standup", dayOffset: 0, hour: 10)
        let before = event(title: "Yesterday", dayOffset: -1, hour: 10)
        let after = event(title: "Next week", dayOffset: 10, hour: 10)

        let filtered = CalendarEventFilter.events(
            in: window,
            from: [before, inside, after]
        )

        XCTAssertEqual(filtered.map(\.title), ["Standup"])
    }

    func testEventFilterSortsByStartDate() {
        let window = CalendarLookahead.window(referenceDate: referenceDate(), calendar: calendar)
        let later = event(title: "Later", dayOffset: 1, hour: 14)
        let earlier = event(title: "Earlier", dayOffset: 0, hour: 9)

        let filtered = CalendarEventFilter.events(in: window, from: [later, earlier])
        XCTAssertEqual(filtered.map(\.title), ["Earlier", "Later"])
    }

    // MARK: - Busy day heuristic

    func testBusyDayWhenFourOrMoreEvents() {
        let dayStart = calendar.startOfDay(for: referenceDate())
        let events = (0 ..< 4).map { event(title: "Meeting \($0)", dayOffset: 0, hour: 9 + $0) }

        XCTAssertTrue(
            CalendarBusyDayPolicy.isBusyDay(eventsOnDay: events, calendar: calendar, dayStart: dayStart)
        )
    }

    func testBusyDayWhenThreeMeetingsBeforeFivePM() {
        let dayStart = calendar.startOfDay(for: referenceDate())
        let events = [
            event(title: "A", dayOffset: 0, hour: 9),
            event(title: "B", dayOffset: 0, hour: 11),
            event(title: "C", dayOffset: 0, hour: 14),
        ]

        XCTAssertTrue(
            CalendarBusyDayPolicy.isBusyDay(eventsOnDay: events, calendar: calendar, dayStart: dayStart)
        )
    }

    func testNotBusyWithTwoMeetingsBeforeFivePM() {
        let dayStart = calendar.startOfDay(for: referenceDate())
        let events = [
            event(title: "A", dayOffset: 0, hour: 9),
            event(title: "B", dayOffset: 0, hour: 11),
        ]

        XCTAssertFalse(
            CalendarBusyDayPolicy.isBusyDay(eventsOnDay: events, calendar: calendar, dayStart: dayStart)
        )
    }

    func testEveningMeetingsDoNotCountTowardBeforeFivePMThreshold() {
        let dayStart = calendar.startOfDay(for: referenceDate())
        let events = [
            event(title: "A", dayOffset: 0, hour: 9),
            event(title: "B", dayOffset: 0, hour: 18),
            event(title: "C", dayOffset: 0, hour: 19),
        ]

        XCTAssertFalse(
            CalendarBusyDayPolicy.isBusyDay(eventsOnDay: events, calendar: calendar, dayStart: dayStart)
        )
    }

    // MARK: - Summary assembly

    func testSummaryMentionsMeetingsBeforeFivePMOnWeekday() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let events = [
            event(on: monday, dayOffset: 3, hour: 9, title: "A"),
            event(on: monday, dayOffset: 3, hour: 11, title: "B"),
            event(on: monday, dayOffset: 3, hour: 14, title: "C"),
        ]

        let summary = CalendarSummaryFormatter.assembleSummary(
            events: events,
            referenceDate: monday,
            calendar: calendar
        )

        XCTAssertTrue(summary.contains("Thursday: A"))
        XCTAssertTrue(summary.contains("B"))
        XCTAssertTrue(summary.contains("C"))
        XCTAssertTrue(summary.contains("(busy)"))
    }

    func testSummaryUsesTomorrowLabel() {
        let events = [
            event(title: "Dentist", dayOffset: 1, hour: 14),
        ]

        let summary = CalendarSummaryFormatter.assembleSummary(
            events: events,
            referenceDate: referenceDate(),
            calendar: calendar
        )

        XCTAssertTrue(summary.contains("Tomorrow: Dentist"))
    }

    func testSummaryIncludesTodayLine() {
        let events = [
            event(title: "A", dayOffset: 0, hour: 10),
            event(title: "B", dayOffset: 0, hour: 15),
        ]

        let summary = CalendarSummaryFormatter.assembleSummary(
            events: events,
            referenceDate: referenceDate(),
            calendar: calendar
        )

        XCTAssertTrue(summary.contains("Today: A"))
        XCTAssertTrue(summary.contains("B"))
    }

    func testSummaryWhenNoEventsInWindow() {
        let summary = CalendarSummaryFormatter.assembleSummary(
            events: [],
            referenceDate: referenceDate(),
            calendar: calendar
        )

        XCTAssertEqual(summary, "No calendar events in the next 8 days.")
    }

    func testBusyDayChipTitleOnlyForToday() {
        let todayBusy = [
            event(title: "A", dayOffset: 0, hour: 9),
            event(title: "B", dayOffset: 0, hour: 11),
            event(title: "C", dayOffset: 0, hour: 14),
        ]
        let tomorrowBusy = [
            event(title: "A", dayOffset: 1, hour: 9),
            event(title: "B", dayOffset: 1, hour: 11),
            event(title: "C", dayOffset: 1, hour: 14),
        ]

        XCTAssertEqual(
            CalendarSummaryFormatter.busyDayChipTitle(
                events: todayBusy,
                referenceDate: referenceDate(),
                calendar: calendar
            ),
            "Busy day"
        )
        XCTAssertNil(
            CalendarSummaryFormatter.busyDayChipTitle(
                events: tomorrowBusy,
                referenceDate: referenceDate(),
                calendar: calendar
            )
        )
    }

    func testSummaryIncludesEventTitlesAndTimes() {
        let events = [
            event(title: "Team sync", dayOffset: 1, hour: 10, minute: 30),
        ]

        let summary = CalendarSummaryFormatter.assembleSummary(
            events: events,
            referenceDate: referenceDate(),
            calendar: calendar
        )

        XCTAssertTrue(summary.contains("Team sync"))
        XCTAssertFalse(summary.contains("1 events"))
    }

    func testCoachContextIncludesScheduleSectionWhenCalendarPresent() {
        let context = CoachContext(
            userSummary: "You, goal: Hypertrophy, 4 days/week, target RIR 2.",
            activeInsights: [],
            derivedMetricsSummary: "ACWR: 1.0 (Optimal).",
            ragSummaries: [],
            recentWorkouts: [],
            calendarSummary: "Today: Standup 10:00, Review 15:00. Thursday: A 9:00, B 11:00, C 14:00 (busy)."
        )

        let prompt = context.assembledPrompt(query: "Should I train hard tomorrow?")
        XCTAssertTrue(prompt.contains("## Schedule"))
        XCTAssertTrue(prompt.contains("Standup"))
        XCTAssertTrue(prompt.contains("C 14:00"))
    }
}
