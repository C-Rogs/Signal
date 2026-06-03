import Foundation
import Testing
@testable import Signal

struct ReadinessFlagEvaluatorTests {
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
        wristTemp: Double? = nil
    ) -> DailyMetricSnapshot {
        DailyMetricSnapshot(
            date: date,
            hrvSDNN: hrv,
            restingHR: rhr,
            activeEnergy: nil,
            sleepHours: 7,
            bodyMassKg: nil,
            stepCount: nil,
            appleExerciseMinutes: nil,
            wristTemperatureDeltaC: wristTemp
        )
    }

    @Test func singleElevatedRHRProducesNoticeAssessment() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let stableHRV = Array(repeating: 52.0, count: 30)
        let metrics = (-29...0).enumerated().map { index, offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: stableHRV[index],
                rhr: offset == 0 ? 66 : 60
            )
        }
        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        let assessment = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: metrics,
                recoveryScore: score,
                referenceDay: end,
                calendar: calendar
            )
        )
        #expect(assessment != nil)
        #expect(assessment?.signals.count == 1)
        #expect(assessment?.aggregateSeverity == .notice)
        #expect(assessment?.signals.contains(where: { $0.kind == .restingHRElevated }) == true)
    }

    @Test func twoSignalsProduceCautionSeverity() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var values = Array(repeating: 55.0, count: 23)
        values.append(contentsOf: Array(repeating: 28.0, count: 7))
        let metrics = (-29...0).enumerated().map { index, offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: values[index],
                rhr: offset == 0 ? 66 : 60
            )
        }
        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        let assessment = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: metrics,
                recoveryScore: score,
                referenceDay: end,
                calendar: calendar
            )
        )
        #expect(assessment?.aggregateSeverity == .caution)
        #expect(assessment?.signals.count == 2)
    }

    @Test func wristTemperatureFlagWhenDeltaAboveThreshold() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-14...0).map { offset in
            snapshot(
                date: day(offset: offset, from: end),
                hrv: 50,
                rhr: 60,
                wristTemp: offset == 0 ? 0.6 : 0.1
            )
        }
        let score = RecoveryScoreCalculator.compute(metrics: metrics, referenceDay: end, calendar: calendar)
        let assessment = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: metrics,
                recoveryScore: score,
                referenceDay: end,
                calendar: calendar
            )
        )
        #expect(assessment?.signals.contains(where: { $0.kind == .wristTemperatureElevated }) == true)
    }

    @Test func recoveryStrainRuleRequiresTwoSignals() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: end)
        var values = Array(repeating: 55.0, count: 23)
        values.append(contentsOf: Array(repeating: 28.0, count: 7))
        let dailySamples = (-29...0).enumerated().map { index, offset in
            DailyMetricSample(
                date: day(offset: offset, from: end),
                hrvSDNN_ms: values[index],
                restingHR: offset == 0 ? 66 : 60,
                sleepHours: 7,
                wristTemperatureDeltaC: nil
            )
        }
        let snapshot = ReflectionSnapshot(
            referenceDate: end,
            isoWeek: isoWeek,
            volumeRows: [],
            acwr: nil,
            exerciseProgress: [],
            dailyMetrics: dailySamples,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: nil,
                averageSleepHours: nil
            )
        )
        let rules = ReflectionRules.recoveryStrainRules(
            snapshot: snapshot,
            referenceDate: end,
            calendar: calendar
        )
        #expect(rules.count == 1)
        #expect(rules.first?.type == .recoveryStrain)
    }
}
