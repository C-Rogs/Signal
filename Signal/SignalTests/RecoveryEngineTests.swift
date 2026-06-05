import Foundation
import Testing
@testable import Signal

struct RecoveryEngineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(offset: Int, from end: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: end)!
    }

    private func snapshot(
        date: Date,
        hrv: Double?,
        rhr: Double? = nil,
        sleep: Double? = nil
    ) -> DailyMetricSnapshot {
        DailyMetricSnapshot(
            date: date,
            hrvSDNN: hrv,
            restingHR: rhr,
            activeEnergy: nil,
            sleepHours: sleep,
            bodyMassKg: nil,
            stepCount: nil,
            appleExerciseMinutes: nil,
            wristTemperatureDeltaC: nil
        )
    }

    @Test func rollingMeansUsesWindowedSamples() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-9...0).map { offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: 50 + Double(offset),
                rhr: 60
            )
        }
        let means = RecoveryEngine.rollingMeans(metrics: metrics, referenceDay: end, calendar: calendar)

        #expect(means.sevenDay.hrvSDNN != nil)
        #expect(means.thirtyDay.sampleDays == 10)
        #expect(means.sixtyDay.sampleDays == 10)
    }

    @Test func elevatedHRVWithLowerRHRAndMoreSleepScoresAboveSeventy() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let hrvValues = Array(repeating: 50.0, count: 23) + Array(repeating: 72.0, count: 7)
        let metrics = (-29...0).enumerated().map { index, offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: hrvValues[index],
                rhr: offset == 0 ? 55 : 60,
                sleep: offset == 0 ? 8.5 : 7
            )
        }

        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        #expect(score.hrvClassification == .aboveUpperBand)
        #expect(score.value > 70)
    }

    @Test func suppressedHRVWithElevatedRHRScoresBelowThirty() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 55.0, count: 23)
        values.append(contentsOf: Array(repeating: 28.0, count: 7))
        let metrics = (-29...0).enumerated().map { index, offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: values[index],
                rhr: offset == 0 ? 68 : 60,
                sleep: 7
            )
        }

        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        #expect(score.hrvClassification == .belowLowerBand)
        #expect(score.value < 30)
    }

    @Test func insufficientDataWithoutRHRAndSleepScoresFifty() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-9...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrv: 50)
        }

        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        #expect(score.hrvClassification == .insufficientData)
        #expect(score.value == 50)
    }

    @Test func hrvSuppressedRuleFiresAfterSustainedLowBand() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let ref = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: ref)
        let days = (0..<25).compactMap { offset -> DailyMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            let value: Double = offset < 10 ? 28 : 55
            return DailyMetricSample(
                date: date,
                hrvSDNN_ms: value,
                restingHR: nil,
                sleepHours: nil,
                wristTemperatureDeltaC: nil
            )
        }
        let snapshot = ReflectionSnapshot(
            referenceDate: ref,
            isoWeek: isoWeek,
            volumeRows: [],
            acwr: nil,
            exerciseProgress: [],
            dailyMetrics: days,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: nil,
                averageSleepHours: nil
            ),
            activeDisruptors: [],
            personalReadiness: nil,
            exertionDebt: nil,
            todayExertion: nil,
            deloadSuggested: false
        )
        let rules = ReflectionRules.hrvSuppressedRules(
            snapshot: snapshot,
            referenceDate: ref,
            calendar: calendar
        )
        #expect(rules.count == 1)

        let blockedDays = (0..<25).compactMap { offset -> DailyMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            let value: Double = offset < 2 ? 28 : 55
            return DailyMetricSample(
                date: date,
                hrvSDNN_ms: value,
                restingHR: nil,
                sleepHours: nil,
                wristTemperatureDeltaC: nil
            )
        }
        let blockedSnapshot = ReflectionSnapshot(
            referenceDate: ref,
            isoWeek: isoWeek,
            volumeRows: [],
            acwr: nil,
            exerciseProgress: [],
            dailyMetrics: blockedDays,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: nil,
                averageSleepHours: nil
            ),
            activeDisruptors: [],
            personalReadiness: nil,
            exertionDebt: nil,
            todayExertion: nil,
            deloadSuggested: false
        )
        let blocked = ReflectionRules.hrvSuppressedRules(
            snapshot: blockedSnapshot,
            referenceDate: ref,
            calendar: calendar
        )
        #expect(blocked.isEmpty)
    }

    @Test func scoreClampedAtZeroAndOneHundred() {
        let high = RecoveryScoreCalculator.composeBreakdown(
            classification: .aboveUpperBand,
            rhrDelta: -5,
            sleepDelta: 2
        )
        #expect(high.total == 90)

        let low = RecoveryScoreCalculator.composeBreakdown(
            classification: .belowLowerBand,
            rhrDelta: 10,
            sleepDelta: -2
        )
        #expect(low.total == 0)
    }

    @Test func confidenceThresholds() {
        #expect(RecoveryScoreCalculator.confidence(forHRVDataPoints: 10) == .low)
        #expect(RecoveryScoreCalculator.confidence(forHRVDataPoints: 13) == .low)
        #expect(RecoveryScoreCalculator.confidence(forHRVDataPoints: 14) == .medium)
        #expect(RecoveryScoreCalculator.confidence(forHRVDataPoints: 29) == .medium)
        #expect(RecoveryScoreCalculator.confidence(forHRVDataPoints: 30) == .high)
    }
}
