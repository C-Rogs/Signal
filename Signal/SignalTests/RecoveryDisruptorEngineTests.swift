import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct RecoveryDisruptorEngineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeContainer() throws -> ModelContainer {
        try SignalModelContainer.make(inMemoryOnly: true)
    }

    private func day(offset: Int, from end: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: end)!
    }

    private func sample(date: Date, sleep: Double, rhr: Double, hrv: Double) -> DailyMetricSample {
        DailyMetricSample(
            date: date,
            hrvSDNN_ms: hrv,
            restingHR: rhr,
            sleepHours: sleep,
            wristTemperatureDeltaC: nil
        )
    }

    @Test func tagAlcoholLastNightCreatesUserEpisode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_086_400))

        try RecoveryDisruptorEngine.tagAlcoholLastNight(
            in: context,
            calendar: calendar,
            referenceDate: reference
        )

        #expect(
            RecoveryDisruptorEngine.hasUserAlcoholTagForYesterday(
                in: context,
                calendar: calendar,
                referenceDate: reference
            )
        )
        #expect(
            RecoveryDisruptorEngine.canUndoTodayAlcoholTag(
                in: context,
                calendar: calendar,
                referenceDate: reference
            )
        )
    }

    @Test func undoTodayAlcoholTagRemovesEpisode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_086_400))

        try RecoveryDisruptorEngine.tagAlcoholLastNight(
            in: context,
            calendar: calendar,
            referenceDate: reference
        )
        let removed = try RecoveryDisruptorEngine.undoTodayUserTag(
            kind: .alcohol,
            in: context,
            calendar: calendar,
            referenceDate: reference
        )
        #expect(removed == true)
        #expect(
            !RecoveryDisruptorEngine.hasUserAlcoholTagForYesterday(
                in: context,
                calendar: calendar,
                referenceDate: reference
            )
        )
    }

    @Test func alcoholProxyInferenceFiresOnShortSleepElevatedRHRAndSuppressedHRV() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let prior = day(offset: -1, from: end)
        let baselineHRV = Array(repeating: 55.0, count: 23) + Array(repeating: 35.0, count: 7)
        let metrics = (-29...0).enumerated().map { index, offset in
            sample(
                date: day(offset: offset, from: end),
                sleep: offset == -1 ? 5.5 : 7.0,
                rhr: offset == -1 ? 68 : 60,
                hrv: baselineHRV[index]
            )
        }
        let metricSnapshots = metrics.map { sample in
            DailyMetricSnapshot(
                date: sample.date,
                hrvSDNN: sample.hrvSDNN_ms,
                restingHR: sample.restingHR,
                activeEnergy: nil,
                sleepHours: sample.sleepHours,
                bodyMassKg: nil,
                stepCount: nil,
                appleExerciseMinutes: nil,
                wristTemperatureDeltaC: sample.wristTemperatureDeltaC
            )
        }

        let snapshot = ReflectionSnapshot(
            referenceDate: end,
            isoWeek: ISOWeekIdentifier.current(calendar: calendar, referenceDate: end),
            volumeRows: [],
            acwr: nil,
            exerciseProgress: [],
            dailyMetrics: metrics,
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

        let candidates = RecoveryDisruptorEngine.inferCandidates(
            snapshot: snapshot,
            metricSnapshots: metricSnapshots,
            referenceDay: end,
            calendar: calendar
        )
        #expect(candidates.contains { $0.kind == .alcohol })
    }

    @Test func trainingLoadPreferredOverAlcoholWhenBothFire() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let baselineHRV = Array(repeating: 55.0, count: 23) + Array(repeating: 35.0, count: 7)
        let metrics = (-29...0).enumerated().map { index, offset in
            sample(
                date: day(offset: offset, from: end),
                sleep: offset == -1 ? 5.5 : 7.0,
                rhr: offset == -1 ? 68 : 60,
                hrv: baselineHRV[index]
            )
        }
        let metricSnapshots = metrics.map { sample in
            DailyMetricSnapshot(
                date: sample.date,
                hrvSDNN: sample.hrvSDNN_ms,
                restingHR: sample.restingHR,
                activeEnergy: nil,
                sleepHours: sample.sleepHours,
                bodyMassKg: nil,
                stepCount: nil,
                appleExerciseMinutes: nil,
                wristTemperatureDeltaC: sample.wristTemperatureDeltaC
            )
        }
        let snapshot = ReflectionSnapshot(
            referenceDate: end,
            isoWeek: ISOWeekIdentifier.current(calendar: calendar, referenceDate: end),
            volumeRows: [],
            acwr: ACWRResult(acuteLoad: 30, chronicLoad: 10, acwr: 1.8, zone: .overreach),
            exerciseProgress: [],
            dailyMetrics: metrics,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: .overreach,
                averageSleepHours: nil
            ),
            activeDisruptors: [],
            personalReadiness: nil,
            exertionDebt: nil,
            todayExertion: nil,
            deloadSuggested: false
        )

        let candidates = RecoveryDisruptorEngine.inferCandidates(
            snapshot: snapshot,
            metricSnapshots: metricSnapshots,
            referenceDay: end,
            calendar: calendar
        )
        #expect(candidates.contains { $0.kind == .trainingLoad })
        #expect(!candidates.contains { $0.kind == .alcohol })
    }

    @Test func calendarCandidateUpsertsInferredAlcoholEpisode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_086_400))
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: reference) else { return }

        let candidate = CalendarDisruptorCandidate(
            eventTitle: "pub night",
            eveningStartDay: yesterday,
            confidence: CalendarDisruptorHeuristics.userPhraseMatchConfidence,
            tier: .userPhrase,
            dedupeKey: CalendarDisruptorHeuristics.calendarInferredDedupeKey(
                eveningStartDay: yesterday,
                calendar: calendar
            )
        )
        RecoveryDisruptorEngine.upsertCalendarCandidate(candidate, in: context)

        let episodes = RecoveryDisruptorEngine.activeEpisodes(
            in: context,
            referenceDay: reference,
            calendar: calendar
        )
        #expect(episodes.contains { $0.kind == .alcohol && $0.inferredEventTitle == "pub night" })
        #expect(episodes.contains { $0.dedupeKey.hasPrefix("calendar.alcohol.") })
    }

    @Test func calendarInferenceDoesNotDowngradeUserTag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_086_400))
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: reference) else { return }

        try RecoveryDisruptorEngine.tagAlcoholLastNight(
            in: context,
            calendar: calendar,
            referenceDate: reference
        )

        let candidate = CalendarDisruptorCandidate(
            eventTitle: "pub night",
            eveningStartDay: yesterday,
            confidence: CalendarDisruptorHeuristics.userPhraseMatchConfidence,
            tier: .userPhrase,
            dedupeKey: CalendarDisruptorHeuristics.calendarInferredDedupeKey(
                eveningStartDay: yesterday,
                calendar: calendar
            )
        )
        RecoveryDisruptorEngine.upsertCalendarCandidate(candidate, in: context)

        let userTagKey = RecoveryDisruptorHeuristics.userTagDedupeKey(
            kind: .alcohol,
            startDay: yesterday,
            calendar: calendar
        )
        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>(
            predicate: #Predicate { $0.dedupeKey == userTagKey }
        )
        let tagged = (try? context.fetch(descriptor))?.first
        #expect(tagged?.source == .userTag)
        #expect(tagged?.confidence == 1.0)
    }

    @Test func healthAndCalendarMergeKeepsHigherConfidence() {
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: end) else { return }

        let calendarCandidate = CalendarDisruptorCandidate(
            eventTitle: "pub night",
            eveningStartDay: yesterday,
            confidence: 0.85,
            tier: .userPhrase,
            dedupeKey: CalendarDisruptorHeuristics.calendarInferredDedupeKey(
                eveningStartDay: yesterday,
                calendar: calendar
            )
        )
        let health = InferredDisruptorCandidate(
            kind: .alcohol,
            startDay: end,
            confidence: 0.6,
            dedupeKey: RecoveryDisruptorHeuristics.inferredDedupeKey(
                kind: .alcohol,
                day: end,
                calendar: calendar
            )
        )

        let merged = RecoveryDisruptorEngine.mergeCalendarAndHealthAlcohol(
            calendarCandidate: calendarCandidate,
            health: health,
            calendar: calendar
        )
        #expect(merged.confidence == 0.85)
        #expect(merged.dedupeKey.hasPrefix("calendar.alcohol."))
        #expect(merged.inferredEventTitle == "pub night")
    }
}
