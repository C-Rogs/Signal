import Foundation
import SwiftData

struct ExertionContext: Sendable, Equatable {
    let exertionDebt: ExertionDebtSummary
    let deloadSuggested: Bool
}

enum ExertionContextBuilder {
    @MainActor
    static func build(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar,
        acwr: ACWRResult? = nil
    ) -> ExertionContext {
        let ref = calendar.startOfDay(for: referenceDay)
        let metrics = fetchMetricSnapshots(in: context, referenceDay: ref, calendar: calendar)
        let sessions = fetchWorkoutDaySessions(in: context, referenceDay: ref, calendar: calendar)
        let resolvedACWR = acwr ?? DeloadConditionEvaluator.acwr(
            on: ref,
            sessions: sessions,
            calendar: calendar
        )
        let debt = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: sessions,
            referenceDay: ref,
            calendar: calendar
        )
        let deload = DeloadConditionEvaluator.deloadSuggested(
            acwr: resolvedACWR,
            exertionDebt: debt,
            metrics: metrics,
            sessions: sessions,
            referenceDay: ref,
            calendar: calendar
        )
        return ExertionContext(exertionDebt: debt, deloadSuggested: deload)
    }

    @MainActor
    static func fetchMetricSnapshots(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar
    ) -> [DailyMetricSnapshot] {
        guard let start = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.debtHistoryDays - 1),
            to: referenceDay
        ) else { return [] }

        let descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date >= start && $0.date <= referenceDay },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { DailyMetricSnapshot(metric: $0) }
    }

    @MainActor
    static func fetchWorkoutDaySessions(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar
    ) -> [WorkoutDaySession] {
        guard let start = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.debtHistoryDays - 1),
            to: referenceDay
        ) else { return [] }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil && session.date >= start && session.date <= referenceDay
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        return ExertionScoreCalculator.workoutDaySessions(from: sessions, calendar: calendar)
    }

    @MainActor
    static func buildAsync(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar,
        acwr: ACWRResult? = nil
    ) async -> ExertionContext {
        let ref = calendar.startOfDay(for: referenceDay)
        let metrics = fetchMetricSnapshots(in: context, referenceDay: ref, calendar: calendar)
        guard let start = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.debtHistoryDays - 1),
            to: ref
        ) else {
            return ExertionContext(
                exertionDebt: ExertionDebtSummary(
                    rolling7dSum: 0,
                    exertionDebtNormalized: 0,
                    yesterdayScore: nil,
                    personalP90Daily: nil,
                    personalP90Rolling7d: nil,
                    todayExertion: nil,
                    isCalibrated: false
                ),
                deloadSuggested: false
            )
        }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil && session.date >= start && session.date <= ref
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let workoutSessions = (try? context.fetch(descriptor)) ?? []
        let sessions = await HealthKitEffortScoreReader.enrichedWorkoutDaySessions(
            from: workoutSessions,
            calendar: calendar
        )
        let resolvedACWR = acwr ?? DeloadConditionEvaluator.acwr(
            on: ref,
            sessions: sessions,
            calendar: calendar
        )
        let debt = ExertionDebtCalculator.summary(
            metrics: metrics,
            sessions: sessions,
            referenceDay: ref,
            calendar: calendar
        )
        let deload = DeloadConditionEvaluator.deloadSuggested(
            acwr: resolvedACWR,
            exertionDebt: debt,
            metrics: metrics,
            sessions: sessions,
            referenceDay: ref,
            calendar: calendar
        )
        return ExertionContext(exertionDebt: debt, deloadSuggested: deload)
    }
}
