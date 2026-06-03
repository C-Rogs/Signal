import Foundation
import Testing
@testable import Signal

struct HRVAnalyzerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func series(
        values: [Double],
        endingAt end: Date
    ) -> [(date: Date, sdnn: Double)] {
        values.enumerated().map { index, value in
            let offset = index - (values.count - 1)
            let date = calendar.date(byAdding: .day, value: offset, to: end)!
            return (date: date, sdnn: value)
        }
    }

    @Test func aboveUpperBandWhenAcuteExceedsBand() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 50.0, count: 20)
        values.replaceSubrange((values.count - 7)..., with: Array(repeating: 72.0, count: 7))
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .aboveUpperBand)
    }

    @Test func belowLowerBandWhenAcuteFallsBelowBand() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 55.0, count: 20)
        values.replaceSubrange((values.count - 7)..., with: Array(repeating: 28.0, count: 7))
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .belowLowerBand)
    }

    @Test func withinBandForNormalFluctuation() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let values = (0..<20).map { 48.0 + Double($0 % 4) }
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .withinBand)
    }

    @Test func insufficientDataAtThirteenPoints() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let values = Array(repeating: 50.0, count: 13)
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .insufficientData)
    }

    @Test func withinBandAtExactlyFourteenPoints() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let values = (0..<14).map { 48.0 + Double($0 % 4) }
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .withinBand)
    }

    @Test func insufficientDataWhenBaselineSDIsZero() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let values = Array(repeating: 45.0, count: 20)
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.classification == .insufficientData)
    }

    @Test func acuteMeanUsesOnlyLastSevenDays() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 40.0, count: 53)
        values.append(contentsOf: Array(repeating: 100.0, count: 7))
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.acuteMean == 100)
    }

    @Test func baselineUsesAtMostLastSixtyPoints() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 10.0, count: 30)
        values.append(contentsOf: Array(repeating: 50.0, count: 60))
        let analysis = HRVAnalyzer.analyze(series(values: values, endingAt: end))
        #expect(analysis.baselineMean == 50)
    }
}
