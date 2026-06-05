import Foundation
import Testing
@testable import Signal

struct ExertionScoreCalculatorTests {
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
        rhr: Double = 60,
        hrMax: Double? = nil
    ) -> DailyMetricSnapshot {
        DailyMetricSnapshot(
            date: date,
            hrvSDNN: 50,
            restingHR: rhr,
            activeEnergy: nil,
            sleepHours: 7,
            bodyMassKg: nil,
            stepCount: nil,
            appleExerciseMinutes: nil,
            wristTemperatureDeltaC: nil,
            heartRateMax: hrMax
        )
    }

    private func session(date: Date, sets: Int, rpe: Double? = nil) -> WorkoutDaySession {
        WorkoutDaySession(
            date: date,
            workingSetCount: sets,
            meanRPE: rpe,
            hkEffortScore: nil
        )
    }

    @Test func hrStrainClampsToZeroOneHundred() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: offset == 0 ? 180 : 170)
        }
        let sessions = [session(date: end, sets: 10)]
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        let score = ExertionScoreCalculator.score(
            for: end,
            metrics: metrics,
            sessions: sessions,
            baselines: baselines,
            calendar: calendar
        )

        #expect(score != nil)
        #expect(score!.hrComponent == 100)
        #expect(score!.value >= 0)
        #expect(score!.value <= 100)
        #expect(score!.source == .blended)
    }

    @Test func blendUsesSixtyFortyWeights() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: offset == 0 ? 140 : 170)
        }
        let sessions = (-27...0).map { offset in
            session(date: day(offset: offset, from: end), sets: 10)
        }
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        let score = ExertionScoreCalculator.score(
            for: end,
            metrics: metrics,
            sessions: sessions,
            baselines: baselines,
            calendar: calendar
        )

        #expect(score != nil)
        let hr = score!.hrComponent!
        let vol = score!.volumeComponent!
        let expected = ExertionHeuristics.hrStrainWeight * hr + ExertionHeuristics.volumeWeight * vol
        #expect(abs(score!.value - expected) < 0.01)
    }

    @Test func rpeFallbackWhenNoHR() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let sessions = (-27...0).map { offset in
            session(date: day(offset: offset, from: end), sets: 8, rpe: offset == 0 ? 8 : 7)
        }
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        let score = ExertionScoreCalculator.score(
            for: end,
            metrics: metrics,
            sessions: sessions,
            baselines: baselines,
            calendar: calendar
        )

        #expect(score != nil)
        #expect(score!.source == .blended)
        #expect(score!.hrComponent == nil)
    }

    @Test func sparseHRUsesFloor() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = [snapshot(date: end)]
        let sessions = [session(date: end, sets: 5)]
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        #expect(baselines.hrMax30d == ExertionHeuristics.hrMaxFloor)
    }

    @Test func calibrationRequiresSevenHRDaysOrFiveWorkouts() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-6...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: 150)
        }
        let sessions = (0..<4).map { index in
            session(date: day(offset: -index, from: end), sets: 5)
        }
        let baselines = ExertionScoreCalculator.baselines(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )
        #expect(baselines.isCalibrated == true)

        let fewHR = (-2...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: 150)
        }
        let fewWorkouts = [session(date: end, sets: 5)]
        let uncalibrated = ExertionScoreCalculator.baselines(
            metrics: fewHR,
            sessions: fewWorkouts,
            referenceDay: end,
            calendar: calendar
        )
        #expect(uncalibrated.isCalibrated == false)
    }
}
