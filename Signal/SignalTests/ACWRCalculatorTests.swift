import XCTest
@testable import Signal

final class ACWRCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testNilWhenChronicLoadZero() {
        let reference = day(2026, 6, 3)
        let result = ACWRCalculator.compute(dailyLoads: [], referenceDate: reference, calendar: calendar)
        XCTAssertNil(result)
    }

    func testZoneBelowOptimal() {
        let reference = day(2026, 6, 10)
        let loads = chronicLoads(reference: reference, acutePerDay: 1, chronicPerDay: 10)
        let result = ACWRCalculator.compute(dailyLoads: loads, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(result?.zone, .belowOptimal)
    }

    func testZoneOptimalAtLowerBound() {
        let reference = day(2026, 6, 10)
        let loads = chronicLoads(reference: reference, acutePerDay: 8, chronicPerDay: 10)
        let result = ACWRCalculator.compute(dailyLoads: loads, referenceDate: reference, calendar: calendar)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.acwr, 0.8)
        XCTAssertLessThanOrEqual(result!.acwr, 1.3)
        XCTAssertEqual(result?.zone, .optimal)
    }

    func testZoneOptimalAtUpperBound() {
        let reference = day(2026, 6, 10)
        let loads = chronicLoads(reference: reference, acutePerDay: 11, chronicPerDay: 10)
        let result = ACWRCalculator.compute(dailyLoads: loads, referenceDate: reference, calendar: calendar)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.acwr, 0.8)
        XCTAssertLessThanOrEqual(result!.acwr, 1.3)
        XCTAssertEqual(result?.zone, .optimal)
    }

    func testZoneCautionAboveOptimal() {
        let reference = day(2026, 6, 10)
        let loads = chronicLoads(reference: reference, acutePerDay: 15, chronicPerDay: 10)
        let result = ACWRCalculator.compute(dailyLoads: loads, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(result?.zone, .caution)
    }

    func testZoneOverreachAboveCaution() {
        let reference = day(2026, 6, 10)
        let loads = chronicLoads(reference: reference, acutePerDay: 19, chronicPerDay: 10)
        let result = ACWRCalculator.compute(dailyLoads: loads, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(result?.zone, .overreach)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func chronicLoads(reference: Date, acutePerDay: Int, chronicPerDay: Int) -> [(date: Date, totalSets: Int)] {
        let ref = calendar.startOfDay(for: reference)
        return (0..<28).compactMap { offset -> (Date, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            let sets = offset < 7 ? acutePerDay : chronicPerDay
            return (date, sets)
        }
    }
}
