import Foundation
import os
import SwiftData

enum RecoveryDisruptorEngine {
    @MainActor
    static func tagAlcoholLastNight(in context: ModelContext, calendar: Calendar, referenceDate: Date = Date()) throws {
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        let dedupeKey = RecoveryDisruptorHeuristics.userTagDedupeKey(
            kind: .alcohol,
            startDay: yesterday,
            calendar: calendar
        )

        if let existing = fetchEpisode(dedupeKey: dedupeKey, in: context) {
            existing.source = .userTag
            existing.confidence = 1.0
            existing.taggedAt = referenceDate
            try context.save()
            Log.recovery.info("disruptor kind=alcohol source=userTag confidence=1.0 action=updated")
            return
        }

        context.insert(
            RecoveryDisruptorEpisode(
                startDay: yesterday,
                kind: .alcohol,
                source: .userTag,
                confidence: 1.0,
                taggedAt: referenceDate,
                dedupeKey: dedupeKey
            )
        )
        try context.save()
        Log.recovery.info("disruptor kind=alcohol source=userTag confidence=1.0 action=tagged")
    }

    @MainActor
    static func undoTodayUserTag(
        kind: RecoveryDisruptorKind,
        in context: ModelContext,
        calendar: Calendar,
        referenceDate: Date = Date()
    ) throws -> Bool {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return false }

        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>()
        let rows = ((try? context.fetch(descriptor)) ?? []).filter { episode in
            episode.kind == kind
                && episode.source == .userTag
                && episode.taggedAt.map { $0 >= todayStart && $0 < tomorrow } == true
        }
        guard !rows.isEmpty else { return false }
        for row in rows {
            context.delete(row)
        }
        try context.save()
        Log.recovery.info("disruptor kind=\(kind.rawValue, privacy: .public) source=userTag action=undo")
        return true
    }

    @MainActor
    static func hasUserAlcoholTagForYesterday(
        in context: ModelContext,
        calendar: Calendar,
        referenceDate: Date = Date()
    ) -> Bool {
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return false }
        let dedupeKey = RecoveryDisruptorHeuristics.userTagDedupeKey(
            kind: .alcohol,
            startDay: yesterday,
            calendar: calendar
        )
        return fetchEpisode(dedupeKey: dedupeKey, in: context) != nil
    }

    @MainActor
    static func canUndoTodayAlcoholTag(
        in context: ModelContext,
        calendar: Calendar,
        referenceDate: Date = Date()
    ) -> Bool {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return false }

        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>()
        return ((try? context.fetch(descriptor)) ?? []).contains { episode in
            episode.kind == .alcohol
                && episode.source == .userTag
                && episode.taggedAt.map { $0 >= todayStart && $0 < tomorrow } == true
        }
    }

    @MainActor
    static func activeEpisodes(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar
    ) -> [RecoveryDisruptorEpisodeSnapshot] {
        let ref = calendar.startOfDay(for: referenceDay)
        guard let lookbackStart = calendar.date(
            byAdding: .day,
            value: -RecoveryDisruptorHeuristics.activeEpisodeMaxAgeDays,
            to: ref
        ) else { return [] }

        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>(
            predicate: #Predicate { episode in
                episode.startDay >= lookbackStart && episode.startDay <= ref
            },
            sortBy: [SortDescriptor(\.startDay, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows
            .map(RecoveryDisruptorEpisodeSnapshot.init)
            .filter { PersonalReadinessCalculator.isEpisodeActiveProxy($0, referenceDay: ref, calendar: calendar) }
    }

    @MainActor
    static func inferCalendarEpisodes(
        in context: ModelContext,
        metricSnapshots: [DailyMetricSnapshot],
        acwr: ACWRResult?,
        referenceDate: Date = Date(),
        calendar: Calendar
    ) async {
        let userPhrases = RecoveryPreferences.shared.calendarHintPhrases
        let access = await CalendarEventStore.shared.currentAccessState()
        guard case .authorized = access else {
            Log.calendar.info("calendar disruptor inference skipped access denied")
            return
        }
        guard !hasUserAlcoholTagForYesterday(in: context, calendar: calendar, referenceDate: referenceDate) else {
            Log.calendar.info("calendar disruptor inference skipped user tag exists")
            return
        }
        if let acwr, acwr.acwr > RecoveryDisruptorHeuristics.trainingLoadACWRThreshold {
            Log.calendar.info("calendar disruptor inference skipped training load precedence")
            return
        }

        let window = CalendarDisruptorLookback.window(referenceDate: referenceDate, calendar: calendar)
        let events = await CalendarEventStore.shared.fetchEvents(in: window)
        guard let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: userPhrases,
            metricSnapshots: metricSnapshots,
            referenceDate: referenceDate,
            calendar: calendar
        ) else { return }

        let referenceDay = calendar.startOfDay(for: referenceDate)
        let healthAlcohol = inferAlcohol(
            metricSnapshots: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        )
        let merged = mergeCalendarAndHealthAlcohol(
            calendarCandidate: candidate,
            health: healthAlcohol,
            calendar: calendar
        )
        upsertInferred(merged, in: context)
        try? context.save()
    }

    @MainActor
    static func pendingCalendarConfirmCandidate(
        in context: ModelContext,
        referenceDate: Date = Date(),
        calendar: Calendar
    ) -> CalendarDisruptorCandidate? {
        guard !hasUserAlcoholTagForYesterday(in: context, calendar: calendar, referenceDate: referenceDate) else {
            return nil
        }

        let eveningStartDay = CalendarDisruptorLookback.eveningStartDay(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let dismissKey = CalendarDisruptorHeuristics.confirmDismissKey(
            eveningStartDay: eveningStartDay,
            calendar: calendar
        )
        if UserDefaults.standard.bool(forKey: dismissKey) {
            return nil
        }

        let dedupeKey = CalendarDisruptorHeuristics.calendarInferredDedupeKey(
            eveningStartDay: eveningStartDay,
            calendar: calendar
        )
        guard let episode = fetchEpisode(dedupeKey: dedupeKey, in: context),
              episode.source == .inferred,
              episode.kind == .alcohol,
              let title = episode.inferredEventTitle
        else { return nil }

        guard episode.confidence >= CalendarDisruptorHeuristics.confirmSheetMinimumConfidence,
              episode.confidence <= CalendarDisruptorHeuristics.confirmSheetMaximumConfidence
        else { return nil }

        return CalendarDisruptorCandidate(
            eventTitle: title,
            eveningStartDay: eveningStartDay,
            confidence: episode.confidence,
            tier: .foundationModel,
            dedupeKey: dedupeKey
        )
    }

    @MainActor
    static func dismissCalendarConfirm(for eveningStartDay: Date, calendar: Calendar) {
        let key = CalendarDisruptorHeuristics.confirmDismissKey(
            eveningStartDay: eveningStartDay,
            calendar: calendar
        )
        UserDefaults.standard.set(true, forKey: key)
    }

    @MainActor
    static func calendarRecoveryContextLine(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar
    ) -> String? {
        let episodes = activeEpisodes(in: context, referenceDay: referenceDay, calendar: calendar)
        guard let episode = episodes.first(where: {
            $0.kind == .alcohol
                && $0.source == .inferred
                && $0.dedupeKey.hasPrefix("calendar.alcohol.")
                && $0.inferredEventTitle != nil
        }), let title = episode.inferredEventTitle else { return nil }
        return "Calendar last night: \(title) (inferred alcohol-likely)."
    }

    static func mergeCalendarAndHealthAlcohol(
        calendarCandidate: CalendarDisruptorCandidate,
        health: InferredDisruptorCandidate?,
        calendar: Calendar
    ) -> InferredDisruptorCandidate {
        guard let health, health.kind == .alcohol else {
            return InferredDisruptorCandidate(
                kind: .alcohol,
                startDay: calendarCandidate.eveningStartDay,
                confidence: calendarCandidate.confidence,
                dedupeKey: calendarCandidate.dedupeKey,
                inferredEventTitle: calendarCandidate.eventTitle
            )
        }

        let calendarWinsTie = calendarCandidate.tier == .userPhrase
        let useCalendarKey: Bool
        let confidence: Double
        if calendarCandidate.confidence > health.confidence {
            useCalendarKey = true
            confidence = calendarCandidate.confidence
        } else if health.confidence > calendarCandidate.confidence {
            useCalendarKey = false
            confidence = health.confidence
        } else {
            useCalendarKey = calendarWinsTie
            confidence = calendarCandidate.confidence
        }

        return InferredDisruptorCandidate(
            kind: .alcohol,
            startDay: calendarCandidate.eveningStartDay,
            confidence: confidence,
            dedupeKey: useCalendarKey ? calendarCandidate.dedupeKey : health.dedupeKey,
            inferredEventTitle: calendarCandidate.eventTitle
        )
    }

    @MainActor
    static func upsertCalendarCandidate(
        _ candidate: CalendarDisruptorCandidate,
        in context: ModelContext
    ) {
        upsertInferred(
            InferredDisruptorCandidate(
                kind: .alcohol,
                startDay: candidate.eveningStartDay,
                confidence: candidate.confidence,
                dedupeKey: candidate.dedupeKey,
                inferredEventTitle: candidate.eventTitle
            ),
            in: context
        )
        try? context.save()
    }

    @MainActor
    static func inferEpisodes(
        in context: ModelContext,
        snapshot: ReflectionSnapshot,
        calendar: Calendar
    ) {
        let referenceDay = calendar.startOfDay(for: snapshot.referenceDate)
        let metricSnapshots = snapshot.dailyMetrics.map(dailyMetricSnapshot(from:))
        let candidates = inferCandidates(
            snapshot: snapshot,
            metricSnapshots: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        )

        for candidate in candidates {
            upsertInferred(candidate, in: context)
        }
        try? context.save()
    }

    @MainActor
    static func inferEpisodes(
        in context: ModelContext,
        metrics: [DailyMetricSnapshot],
        acwr: ACWRResult?,
        referenceDay: Date,
        calendar: Calendar
    ) {
        let dailySamples = metrics.map(dailyMetricSample(from:))
        let exertionContext = ExertionContextBuilder.build(
            in: context,
            referenceDay: referenceDay,
            calendar: calendar,
            acwr: acwr
        )
        let snapshot = ReflectionSnapshot(
            referenceDate: referenceDay,
            isoWeek: ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDay),
            volumeRows: [],
            acwr: acwr,
            exerciseProgress: [],
            dailyMetrics: dailySamples,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: acwr?.zone,
                averageSleepHours: nil
            ),
            activeDisruptors: [],
            personalReadiness: nil,
            exertionDebt: exertionContext.exertionDebt,
            todayExertion: exertionContext.exertionDebt.todayExertion,
            deloadSuggested: exertionContext.deloadSuggested
        )
        inferEpisodes(in: context, snapshot: snapshot, calendar: calendar)
    }

    static func inferCandidates(
        snapshot: ReflectionSnapshot,
        metricSnapshots: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> [InferredDisruptorCandidate] {
        var candidates: [InferredDisruptorCandidate] = []

        if let trainingLoad = inferTrainingLoad(snapshot: snapshot, referenceDay: referenceDay, calendar: calendar) {
            candidates.append(trainingLoad)
        }
        if let alcohol = inferAlcohol(
            metricSnapshots: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        ) {
            if !candidates.contains(where: { $0.kind == .trainingLoad }) {
                candidates.append(alcohol)
            }
        }
        if let sleepDebt = inferSleepDebt(snapshot: snapshot, calendar: calendar) {
            candidates.append(sleepDebt)
        }
        if let illnessLike = inferIllnessLike(
            metricSnapshots: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        ) {
            candidates.append(illnessLike)
        }

        return candidates
    }

    private static func inferTrainingLoad(
        snapshot: ReflectionSnapshot,
        referenceDay: Date,
        calendar: Calendar
    ) -> InferredDisruptorCandidate? {
        let debt = snapshot.exertionDebt
        let acwrZone = snapshot.acwr?.zone
        let acwrTriggers = acwrZone == .caution || acwrZone == .overreach
        let debtTriggers = (debt?.exertionDebtNormalized ?? 0) >= ExertionHeuristics.exertionDebtHighThreshold
        let yesterdayP90Triggers: Bool = {
            guard let debt,
                  let yesterday = debt.yesterdayScore,
                  let p90 = debt.personalP90Daily
            else { return false }
            return yesterday >= p90
        }()

        guard acwrTriggers || debtTriggers || yesterdayP90Triggers else { return nil }

        var confidence = RecoveryDisruptorHeuristics.trainingLoadInferenceBaseConfidence
        if let acwr = snapshot.acwr, acwr.acwr > RecoveryDisruptorHeuristics.trainingLoadACWRThreshold {
            confidence += (acwr.acwr - RecoveryDisruptorHeuristics.trainingLoadACWRThreshold) * 0.25
        }
        if debtTriggers, let debt {
            confidence += (debt.exertionDebtNormalized - ExertionHeuristics.exertionDebtHighThreshold) * 0.3
        }
        if yesterdayP90Triggers {
            confidence += 0.15
        }

        if let exertion = snapshot.todayExertion {
            Log.recovery.info(
                "exertion score=\(exertion.value, privacy: .public) debt=\(debt?.exertionDebtNormalized ?? -1, privacy: .public) trainingLoad inference"
            )
        }

        return InferredDisruptorCandidate(
            kind: .trainingLoad,
            startDay: referenceDay,
            confidence: min(1.0, confidence),
            dedupeKey: RecoveryDisruptorHeuristics.inferredDedupeKey(
                kind: .trainingLoad,
                day: referenceDay,
                calendar: calendar
            )
        )
    }

    private static func inferAlcohol(
        metricSnapshots: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> InferredDisruptorCandidate? {
        guard let priorDay = calendar.date(byAdding: .day, value: -1, to: referenceDay) else { return nil }

        let priorScore = RecoveryScoreCalculator.compute(
            metrics: metricSnapshots,
            referenceDay: priorDay,
            calendar: calendar
        )
        let priorMetric = metricSnapshots.first {
            calendar.isDate($0.date, inSameDayAs: priorDay)
        }

        let shortSleep = (priorMetric?.sleepHours ?? 10) < RecoveryDisruptorHeuristics.alcoholProxySleepHoursMax
        let elevatedRHR = (priorScore.rhrDelta ?? 0) > RecoveryDisruptorHeuristics.alcoholProxyRHRElevatedBpm
        let suppressedHRV = priorScore.hrvClassification == .belowLowerBand
            || priorScore.breakdown.hrvTerm < 0

        guard shortSleep, elevatedRHR, suppressedHRV else { return nil }

        var confidence = RecoveryDisruptorHeuristics.alcoholProxyBaseConfidence
        if let wristTemp = priorMetric?.wristTemperatureDeltaC,
           wristTemp >= ReadinessFlagEvaluator.wristTemperatureElevatedDeltaC
        {
            confidence += RecoveryDisruptorHeuristics.alcoholProxyWristTempBonus
        }

        return InferredDisruptorCandidate(
            kind: .alcohol,
            startDay: referenceDay,
            confidence: min(1.0, confidence),
            dedupeKey: RecoveryDisruptorHeuristics.inferredDedupeKey(
                kind: .alcohol,
                day: referenceDay,
                calendar: calendar
            )
        )
    }

    private static func inferSleepDebt(
        snapshot: ReflectionSnapshot,
        calendar: Calendar
    ) -> InferredDisruptorCandidate? {
        let metrics = snapshot.dailyMetrics.filter { $0.sleepHours != nil }
        guard !metrics.isEmpty else { return nil }

        let consecutive = ReflectionRules.trailingConsecutiveDays(
            metrics: metrics,
            calendar: calendar,
            referenceDate: snapshot.referenceDate,
            maxLookback: 10,
            predicate: { ($0.sleepHours ?? 10) < RecoveryDisruptorHeuristics.sleepDebtHoursMax }
        )
        guard consecutive.count >= RecoveryDisruptorHeuristics.sleepDebtConsecutiveDays else { return nil }

        let referenceDay = calendar.startOfDay(for: snapshot.referenceDate)
        return InferredDisruptorCandidate(
            kind: .sleepDebt,
            startDay: referenceDay,
            confidence: 0.8,
            dedupeKey: RecoveryDisruptorHeuristics.inferredDedupeKey(
                kind: .sleepDebt,
                day: referenceDay,
                calendar: calendar
            )
        )
    }

    private static func inferIllnessLike(
        metricSnapshots: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> InferredDisruptorCandidate? {
        let score = RecoveryScoreCalculator.compute(
            metrics: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        )
        let assessment = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: metricSnapshots,
                recoveryScore: score,
                referenceDay: referenceDay,
                calendar: calendar
            )
        )
        guard let assessment,
              assessment.signals.count >= RecoveryDisruptorHeuristics.illnessLikeMinimumSignals
        else { return nil }

        return InferredDisruptorCandidate(
            kind: .illnessLike,
            startDay: referenceDay,
            confidence: 0.7,
            dedupeKey: RecoveryDisruptorHeuristics.inferredDedupeKey(
                kind: .illnessLike,
                day: referenceDay,
                calendar: calendar
            )
        )
    }

    @MainActor
    private static func upsertInferred(_ candidate: InferredDisruptorCandidate, in context: ModelContext) {
        if let existing = fetchEpisode(dedupeKey: candidate.dedupeKey, in: context) {
            if existing.source == .userTag { return }
            existing.confidence = max(existing.confidence, candidate.confidence)
            existing.startDay = candidate.startDay
            if let title = candidate.inferredEventTitle {
                existing.inferredEventTitle = title
            }
            Log.recovery.info(
                "disruptor kind=\(candidate.kind.rawValue, privacy: .public) source=inferred confidence=\(candidate.confidence, privacy: .public) action=updated"
            )
            return
        }

        reconcileConflictingAlcoholEpisode(with: candidate, in: context)

        context.insert(
            RecoveryDisruptorEpisode(
                startDay: candidate.startDay,
                kind: candidate.kind,
                source: .inferred,
                confidence: candidate.confidence,
                inferredEventTitle: candidate.inferredEventTitle,
                dedupeKey: candidate.dedupeKey
            )
        )
        Log.recovery.info(
            "disruptor kind=\(candidate.kind.rawValue, privacy: .public) source=inferred confidence=\(candidate.confidence, privacy: .public) action=inserted"
        )
    }

    @MainActor
    private static func reconcileConflictingAlcoholEpisode(
        with candidate: InferredDisruptorCandidate,
        in context: ModelContext,
        calendar: Calendar = SchedulingCalendar.make()
    ) {
        guard candidate.kind == .alcohol else { return }

        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>()
        let rows = ((try? context.fetch(descriptor)) ?? []).filter { episode in
            episode.kind == .alcohol
                && episode.source == .inferred
                && episode.dedupeKey != candidate.dedupeKey
        }
        for row in rows {
            guard isSameLogicalAlcoholNight(
                lhsStartDay: row.startDay,
                rhsStartDay: candidate.startDay,
                calendar: calendar
            ) else { continue }
            if candidate.confidence >= row.confidence {
                context.delete(row)
            }
        }
    }

    private static func isSameLogicalAlcoholNight(
        lhsStartDay: Date,
        rhsStartDay: Date,
        calendar: Calendar
    ) -> Bool {
        let lhs = calendar.startOfDay(for: lhsStartDay)
        let rhs = calendar.startOfDay(for: rhsStartDay)
        if lhs == rhs { return true }
        if let next = calendar.date(byAdding: .day, value: 1, to: lhs) {
            return next == rhs
        }
        if let prior = calendar.date(byAdding: .day, value: -1, to: lhs) {
            return prior == rhs
        }
        return false
    }

    @MainActor
    private static func fetchEpisode(dedupeKey: String, in context: ModelContext) -> RecoveryDisruptorEpisode? {
        let descriptor = FetchDescriptor<RecoveryDisruptorEpisode>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private static func dailyMetricSnapshot(from sample: DailyMetricSample) -> DailyMetricSnapshot {
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

    private static func dailyMetricSample(from snapshot: DailyMetricSnapshot) -> DailyMetricSample {
        DailyMetricSample(
            date: snapshot.date,
            hrvSDNN_ms: snapshot.hrvSDNN,
            restingHR: snapshot.restingHR,
            sleepHours: snapshot.sleepHours,
            wristTemperatureDeltaC: snapshot.wristTemperatureDeltaC
        )
    }
}

struct InferredDisruptorCandidate: Equatable {
    let kind: RecoveryDisruptorKind
    let startDay: Date
    let confidence: Double
    let dedupeKey: String
    let inferredEventTitle: String?

    init(
        kind: RecoveryDisruptorKind,
        startDay: Date,
        confidence: Double,
        dedupeKey: String,
        inferredEventTitle: String? = nil
    ) {
        self.kind = kind
        self.startDay = startDay
        self.confidence = confidence
        self.dedupeKey = dedupeKey
        self.inferredEventTitle = inferredEventTitle
    }
}

private extension PersonalReadinessCalculator {
    static func isEpisodeActiveProxy(
        _ episode: RecoveryDisruptorEpisodeSnapshot,
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: episode.startDay)
        guard start <= referenceDay else { return false }
        if let endDay = episode.endDay {
            return calendar.startOfDay(for: endDay) >= referenceDay
        }
        let days = calendar.dateComponents([.day], from: start, to: referenceDay).day ?? 0
        return days <= RecoveryDisruptorHeuristics.activeEpisodeMaxAgeDays
    }
}
