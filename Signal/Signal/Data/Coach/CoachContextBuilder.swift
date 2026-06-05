import Foundation
import SwiftData
import os

actor CoachContextBuilder {
    func buildContext(for query: String, modelContainer: ModelContainer) async throws -> CoachContext {
        let route = CoachQueryRouter.classify(query)
        let referenceDate = Date()
        let calendar = SchedulingCalendar.make()
        let metricsSnapshot = await DerivedMetricsService.shared.snapshot(modelContainer: modelContainer)
        let proteinBelowTarget = Self.isProteinBelowTarget(snapshot: metricsSnapshot)
        let scope = CoachContextScope.make(
            route: route,
            query: query,
            proteinBelowTarget: proteinBelowTarget
        )

        let ragSummaries: [String]
        if scope.ragK > 0 {
            ragSummaries = try await HealthVectorRetriever.retrieve(
                query: query,
                k: scope.ragK,
                modelContainer: modelContainer,
                referenceDate: referenceDate,
                calendar: calendar
            )
        } else {
            ragSummaries = []
        }

        let calendarSummary: String
        if scope.includeCalendar {
            calendarSummary = await CalendarContextBuilder().buildSummary(referenceDate: referenceDate) ?? ""
        } else {
            calendarSummary = ""
        }

        return await MainActor.run {
            let userSummary = Self.buildUserSummary(modelContainer: modelContainer)
            let activeInsights = scope.includeActiveInsights
                ? Self.fetchActiveInsights(modelContainer: modelContainer)
                : []
            let derivedMetricsSummary = Self.formatDerivedMetrics(
                snapshot: metricsSnapshot,
                referenceDate: referenceDate,
                calendar: calendar,
                include: scope.metricsParts
            )
            let personalReadinessSummary = scope.includePersonalReadiness
                ? Self.formatPersonalReadiness(modelContainer: modelContainer)
                : ""
            let recentWorkouts = scope.includeRecentWorkouts
                ? Self.buildRecentWorkouts(modelContainer: modelContainer, limit: scope.recentWorkoutLimit)
                : []

            var context = CoachContext(
                userSummary: userSummary,
                activeInsights: activeInsights,
                derivedMetricsSummary: derivedMetricsSummary,
                personalReadinessSummary: personalReadinessSummary,
                ragSummaries: ragSummaries,
                recentWorkouts: recentWorkouts,
                calendarSummary: calendarSummary
            )
            context.prepareForModelInput(query: query, route: route)
            let sectionNames = context.activeSectionNames().joined(separator: ",")
            Log.coach.info(
                "coach intent=\(route.rawValue, privacy: .public) contextSections=\(sectionNames, privacy: .public) promptChars=\(context.assembledPrompt(query: query).count, privacy: .public)"
            )
            return context
        }
    }

    nonisolated private static func isProteinBelowTarget(snapshot: DerivedMetricsSnapshot) -> Bool {
        guard let protein = snapshot.proteinTarget,
              let actual = protein.actualGrams
        else { return false }
        return actual < protein.targetMinGrams
    }

    @MainActor
    private static func buildUserSummary(modelContainer: ModelContainer) -> String {
        let context = ModelContext(modelContainer)
        let goalType = ProfileGoalRepository.primaryGoal(in: context)
        let targetRIR = ProfileGoalRepository.targetRIR(in: context)
        let weeklyDays = (try? ProfileGoalRepository.fetchTrainingGoal(in: context))?.weeklyTrainingDays ?? 4
        return "You, goal: \(goalType.displayName), \(weeklyDays) days/week, target RIR \(targetRIR)."
    }

    @MainActor
    private static func fetchActiveInsights(modelContainer: ModelContainer) -> [String] {
        let context = ModelContext(modelContainer)
        let now = Date()
        let rows = (try? context.fetch(FetchDescriptor<Insight>())) ?? []
        let active = rows.filter { insight in
            guard !insight.isActioned else { return false }
            guard insight.severity == .alert || insight.severity == .warning else { return false }
            if let expires = insight.expiresAt {
                return expires > now
            }
            return true
        }
        .sorted { lhs, rhs in
            let lhsRank = lhs.severity == .alert ? 0 : 1
            let rhsRank = rhs.severity == .alert ? 0 : 1
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.createdAt > rhs.createdAt
        }
        .prefix(3)

        return active.map { "• \($0.bodyText)" }
    }

    @MainActor
    private static func formatDerivedMetrics(
        snapshot: DerivedMetricsSnapshot,
        referenceDate: Date,
        calendar: Calendar,
        include: DerivedMetricsParts = [.acwr, .volume, .protein, .exertion, .strainDebt, .syncFreshness]
    ) -> String {
        var lines: [String] = []

        if include.contains(.acwr) {
            if let acwr = snapshot.acwr {
                let acwrText = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), acwr.acwr)
                lines.append("ACWR: \(acwrText) (\(acwr.zone.badgeLabel)).")
            } else {
                lines.append("ACWR: unavailable.")
            }
        }

        if include.contains(.volume) {
            let volumeParts = snapshot.weeklyVolume
                .filter { $0.fractionalSets > 0 }
                .map { row in
                    let sets = VolumeCalculator.integerSetCount(from: row.fractionalSets)
                    return "\(row.muscleGroup.rawValue) \(sets) sets (\(row.status.badgeLabel))"
                }
            if volumeParts.isEmpty {
                lines.append("Volume this week: no working sets logged.")
            } else {
                lines.append("Volume this week: \(volumeParts.joined(separator: "; ")).")
            }
        }

        if include.contains(.syncFreshness) {
            let clockDayKey = Summarizer.dayKey(for: referenceDate, calendar: calendar)
            if let latestSync = snapshot.healthSyncLatestDayKey,
               latestSync != clockDayKey,
               let dayGap = CoachClockFormatter.calendarDaysBetween(
                   earlierDayKey: latestSync,
                   laterDayKey: clockDayKey,
                   calendar: calendar
               ),
               dayGap > 1
            {
                lines.append("Health sync latest: \(latestSync).")
            }
        }

        if include.contains(.protein),
           let protein = snapshot.proteinTarget,
           let actual = protein.actualGrams,
           actual < protein.targetMinGrams
        {
            let minG = Int(protein.targetMinGrams.rounded())
            let maxG = Int(protein.targetMaxGrams.rounded())
            let actualRounded = Int(actual.rounded())
            lines.append(
                "Protein: \(actualRounded)g today (below target \(minG)-\(maxG)g at \(Int(protein.bodyweightKg))kg)."
            )
        }

        if include.contains(.exertion),
           let exertion = snapshot.todayExertion,
           exertion.isCalibrated
        {
            let scoreInt = Int(exertion.value.rounded())
            lines.append("Exertion today: \(scoreInt)/100 (\(exertion.source.rawValue)).")
        }
        if include.contains(.strainDebt),
           let debt = snapshot.exertionDebt,
           debt.isCalibrated
        {
            let debtText = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), debt.exertionDebtNormalized)
            let sumInt = Int(debt.rolling7dSum.rounded())
            let deloadLabel = snapshot.deloadSuggested ? "yes" : "no"
            lines.append("Strain debt: \(debtText) (7d sum \(sumInt)). Deload suggested: \(deloadLabel).")
        }

        return lines.joined(separator: " ")
    }

    @MainActor
    private static func formatPersonalReadiness(modelContainer: ModelContainer) -> String {
        let context = ModelContext(modelContainer)
        let bundle = RecoveryEngine.todayReadinessBundle(in: context)
        let profile = bundle.profile
        let scoreInt = Int(bundle.score.value.rounded())

        if profile.isCalibrated {
            let norm = Int(profile.personalMedian.rounded())
            let delta = Int(profile.readinessDelta.rounded())
            let sign = delta > 0 ? "+" : ""
            var line = "Recovery norm ~\(norm); today \(scoreInt) (\(sign)\(delta))."
            if profile.activeDisruptors.isEmpty {
                line += " No active disruptors."
            } else if let top = profile.activeDisruptors.first {
                line += " Active: \(top.userFacingLabel)."
            }
            if let calendarLine = calendarRecoveryContextLine(modelContainer: modelContainer) {
                line += " \(calendarLine)"
            }
            return line
        }

        if profile.activeDisruptors.isEmpty {
            var line = "Recovery score \(scoreInt)/100. Personal norm still calibrating."
            if let calendarLine = calendarRecoveryContextLine(modelContainer: modelContainer) {
                line += " \(calendarLine)"
            }
            return line
        }
        let disruptor = profile.activeDisruptors.first?.userFacingLabel ?? "Recovery disrupted"
        var line = "Recovery score \(scoreInt)/100. \(disruptor)."
        if let calendarLine = calendarRecoveryContextLine(modelContainer: modelContainer) {
            line += " \(calendarLine)"
        }
        return line
    }

    @MainActor
    private static func calendarRecoveryContextLine(modelContainer: ModelContainer) -> String? {
        let context = ModelContext(modelContainer)
        let calendar = SchedulingCalendar.make()
        let referenceDay = calendar.startOfDay(for: Date())
        return RecoveryDisruptorEngine.calendarRecoveryContextLine(
            in: context,
            referenceDay: referenceDay,
            calendar: calendar
        )
    }

    @MainActor
    private static func buildRecentWorkouts(modelContainer: ModelContainer, limit: Int = 2) -> [String] {
        guard limit > 0 else { return [] }
        let context = ModelContext(modelContainer)
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            ?? .distantPast
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startTime >= twoWeeksAgo },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let sessions = (try? context.fetch(descriptor)) ?? []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return sessions.map { session in
            let dateLabel = formatter.string(from: session.date)
            let exerciseLines = topExercises(for: session, limit: 3)
            if exerciseLines.isEmpty {
                return "\(dateLabel), \(session.title): (no logged sets)"
            }
            return "\(dateLabel), \(session.title): \(exerciseLines.joined(separator: "; "))"
        }
    }

    @MainActor
    private static func topExercises(for session: WorkoutSession, limit: Int) -> [String] {
        let ranked = session.exercises.compactMap { exercise -> (String, Double)? in
            guard let best = ExerciseE1RMAggregator.bestWorkingSetE1RM(for: exercise) else { return nil }
            let name = exercise.catalogEntry?.canonicalName ?? exercise.exerciseTitle
            let score = best.bestSetWeightKg * Double(best.bestSetReps)
            let weightText = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), best.bestSetWeightKg)
            return ("\(name) \(weightText)kg×\(best.bestSetReps)", score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)

        return Array(ranked)
    }
}
