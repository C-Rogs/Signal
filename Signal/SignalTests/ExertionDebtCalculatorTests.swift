import Foundation
import Testing
@testable import Signal

struct ExertionDebtCalculatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(offset: Int, from end: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: end)!
    }

    private func snapshot(date: Date, hrMax: Double? = 170) -> DailyMetricSnapshot {
        DailyMetricSnapshot(
            date: date,
            hrvSDNN: 50,
            restingHR: 60,
            activeEnergy: nil,
            sleepHours: 7,
            bodyMassKg: nil,
            stepCount: nil,
            appleExerciseMinutes: nil,
            wristTemperatureDeltaC: nil,
            heartRateMax: hrMax
        )
    }

    private func session(date: Date, sets: Int = 12, rpe: Double = 8) -> WorkoutDaySession {
        WorkoutDaySession(
            date: date,
            workingSetCount: sets,
            meanRPE: rpe,
            hkEffortScore: nil
        )
    }

    @Test func rolling7dSumAccumulatesRecentDays() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-59...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: 170)
        }
        let sessions = (-6...0).map { offset in
            session(date: day(offset: offset, from: end))
        }

        let sum = ExertionDebtCalculator.rolling7dSum(
            on: end,
            metrics: metrics,
            sessions: sessions,
            calendar: calendar
        )
        #expect(sum > 0)
    }

    @Test func debtNormalizedClampsZeroToOne() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-59...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: 170)
        }
        let sessions = (-27...0).map { offset in
            session(date: day(offset: offset, from: end))
        }

        let summary = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: sessions,
            referenceDay: end,
            calendar: calendar
        )

        #expect(summary.exertionDebtNormalized >= 0)
        #expect(summary.exertionDebtNormalized <= 1)
        #expect(summary.rolling7dSum >= 0)
    }

    @Test func highRecentLoadIncreasesDebt() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-59...0).map { offset in
            snapshot(date: day(offset: offset, from: end), hrMax: 170)
        }
        let heavySessions = (-6...0).map { offset in
            session(date: day(offset: offset, from: end), sets: 20, rpe: 9)
        }
        let lightSessions = (-27..<(-6)).map { offset in
            session(date: day(offset: offset, from: end), sets: 4, rpe: 6)
        }

        let heavy = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: heavySessions + lightSessions,
            referenceDay: end,
            calendar: calendar
        )
        let light = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: lightSessions,
            referenceDay: end,
            calendar: calendar
        )

        #expect(heavy.exertionDebtNormalized >= light.exertionDebtNormalized)
    }
}
