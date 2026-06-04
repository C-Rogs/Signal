import Foundation
import Testing
@testable import Signal

struct DailyBriefingSchedulerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func nextBriefingFireDateUsesTodayWhenTimeNotPassed() {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15
        components.hour = 6
        components.minute = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let now = calendar.date(from: components)!

        let fire = DailyBriefingScheduler.nextBriefingFireDate(
            from: now,
            briefingHour: 7,
            briefingMinute: 0,
            calendar: calendar
        )

        var expected = components
        expected.hour = 7
        let expectedDate = calendar.date(from: expected)!
        #expect(fire == expectedDate)
    }

    @Test func nextBriefingFireDateUsesTomorrowWhenTimePassed() {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15
        components.hour = 8
        components.minute = 30
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let now = calendar.date(from: components)!

        let fire = DailyBriefingScheduler.nextBriefingFireDate(
            from: now,
            briefingHour: 7,
            briefingMinute: 0,
            calendar: calendar
        )

        var expected = components
        expected.day = 16
        expected.hour = 7
        expected.minute = 0
        let expectedDate = calendar.date(from: expected)!
        #expect(fire == expectedDate)
    }

    @Test func nextBriefingFireDateUsesTodayWhenNowEqualsBriefingTime() {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15
        components.hour = 7
        components.minute = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let now = calendar.date(from: components)!

        let fire = DailyBriefingScheduler.nextBriefingFireDate(
            from: now,
            briefingHour: 7,
            briefingMinute: 0,
            calendar: calendar
        )

        var expected = components
        expected.day = 16
        expected.hour = 7
        let expectedDate = calendar.date(from: expected)!
        #expect(fire == expectedDate)
    }
}
