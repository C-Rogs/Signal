import Foundation
import Testing
@testable import Signal

struct PersonalReadinessCalculatorTests {
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
        hrv: Double = 50,
        rhr: Double = 60,
        sleep: Double = 7
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

    private func recoveryScore(value: Double) -> RecoveryScore {
        RecoveryScore(
            value: value,
            hrvClassification: .withinBand,
            hrvAnalysis: nil,
            rhrDelta: nil,
            sleepDelta: nil,
            confidence: .medium,
            breakdown: RecoveryScoreBreakdown(hrvTerm: 0, rhrTerm: 0, sleepTerm: 0, total: value),
            todayHRV: nil,
            todayRestingHR: nil
        )
    }

    private func episode(
        kind: RecoveryDisruptorKind,
        source: RecoveryDisruptorSource,
        startDay: Date,
        confidence: Double = 1.0
    ) -> RecoveryDisruptorEpisodeSnapshot {
        RecoveryDisruptorEpisodeSnapshot(
            id: UUID(),
            startDay: startDay,
            endDay: nil,
            kind: kind,
            source: source,
            confidence: confidence,
            taggedAt: source == .userTag ? startDay : nil,
            dedupeKey: "test.\(kind.rawValue).\(Int(startDay.timeIntervalSince1970))"
        )
    }

    @Test func calibrationRequiresTwentyOneDays() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-19...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let profile = PersonalReadinessCalculator.compute(
            metrics: metrics,
            todayScore: recoveryScore(value: 50),
            activeEpisodes: [],
            referenceDay: end,
            calendar: calendar
        )
        #expect(profile.daysOfHistory == 20)
        #expect(profile.isCalibrated == false)
    }

    @Test func calibratedProfileComputesPercentiles() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let profile = PersonalReadinessCalculator.compute(
            metrics: metrics,
            todayScore: recoveryScore(value: 52),
            activeEpisodes: [],
            referenceDay: end,
            calendar: calendar
        )
        #expect(profile.isCalibrated == true)
        #expect(profile.daysOfHistory == 30)
        #expect(profile.readinessDelta == profile.todayScore - profile.personalMedian)
    }

    @Test func recoveryDebtDecaysWithHalfLife() {
        let debtDay0 = PersonalReadinessCalculator.recoveryDebt(daysSinceStart: 0, halfLifeDays: 2)
        let debtDay2 = PersonalReadinessCalculator.recoveryDebt(daysSinceStart: 2, halfLifeDays: 2)
        #expect(debtDay0 == 1.0)
        #expect(abs(debtDay2 - 0.5) < 0.001)
    }

    @Test func activeAlcoholEpisodeIncreasesRecoveryDebt() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let yesterday = day(offset: -1, from: end)
        let profile = PersonalReadinessCalculator.compute(
            metrics: metrics,
            todayScore: recoveryScore(value: 48),
            activeEpisodes: [episode(kind: .alcohol, source: .userTag, startDay: yesterday)],
            referenceDay: end,
            calendar: calendar
        )
        #expect(profile.recoveryDebt > 0.5)
        #expect(PersonalReadinessCalculator.hasActiveAlcoholDisruptor(in: profile))
    }

    @Test func inferredAlcoholBelowHighConfidenceUsesGenericLabel() {
        let summary = ActiveDisruptorSummary(
            kind: .alcohol,
            source: .inferred,
            confidence: 0.6,
            daysSinceStart: 0,
            recoveryDebt: 1.0,
            userFacingLabel: PersonalReadinessCalculator.userFacingLabel(
                for: RecoveryDisruptorEpisodeSnapshot(
                    id: UUID(),
                    startDay: Date(),
                    endDay: nil,
                    kind: .alcohol,
                    source: .inferred,
                    confidence: 0.6,
                    taggedAt: nil,
                    dedupeKey: "test"
                )
            )
        )
        #expect(summary.userFacingLabel.contains("disrupted"))
        #expect(!summary.userFacingLabel.lowercased().contains("drank"))
    }

    @Test func exertionDebtReducesAdjustedPercentile() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let profile = PersonalReadinessCalculator.compute(
            metrics: metrics,
            todayScore: recoveryScore(value: 52),
            activeEpisodes: [],
            referenceDay: end,
            calendar: calendar,
            exertionDebtNormalized: 1.0
        )
        #expect(profile.adjustedReadinessPercentile == profile.readinessPercentile - 15)
    }

    @Test func nilExertionDebtLeavesAdjustedUnchanged() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let profile = PersonalReadinessCalculator.compute(
            metrics: metrics,
            todayScore: recoveryScore(value: 52),
            activeEpisodes: [],
            referenceDay: end,
            calendar: calendar
        )
        #expect(profile.adjustedReadinessPercentile == profile.readinessPercentile)
    }

    @Test func learnedAlcoholHalfLifeFromTaggedEpisodes() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metrics = (-29...0).map { offset in
            snapshot(date: day(offset: offset, from: end))
        }
        let episodes = [
            episode(kind: .alcohol, source: .userTag, startDay: day(offset: -10, from: end)),
            episode(kind: .alcohol, source: .userTag, startDay: day(offset: -20, from: end)),
            episode(kind: .alcohol, source: .userTag, startDay: day(offset: -25, from: end)),
        ]
        let learned = PersonalReadinessCalculator.learnedHalfLife(
            for: .alcohol,
            episodes: episodes,
            metrics: metrics,
            personalMedian: 50,
            calendar: calendar
        )
        #expect(learned != nil)
        if let learned {
            #expect(learned >= RecoveryDisruptorHeuristics.learnedHalfLifeMinimumDays)
            #expect(learned <= RecoveryDisruptorHeuristics.learnedHalfLifeMaximumDays)
        }
    }
}
