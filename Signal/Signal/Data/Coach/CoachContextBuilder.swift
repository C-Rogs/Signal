import Foundation
import SwiftData
import os

actor CoachContextBuilder {
    func buildContext(for query: String, modelContainer: ModelContainer) async throws -> CoachContext {
        let ragSummaries = try await RAGRetriever.retrieve(
            query: query,
            k: 4,
            boostDaysWithin: 30,
            modelContainer: modelContainer
        )
        let metricsSnapshot = await DerivedMetricsService.shared.snapshot(modelContainer: modelContainer)

        return await MainActor.run {
            let userSummary = Self.buildUserSummary(modelContainer: modelContainer)
            let activeInsights = Self.fetchActiveInsights(modelContainer: modelContainer)
            let derivedMetricsSummary = Self.formatDerivedMetrics(snapshot: metricsSnapshot)
            let recentWorkouts = Self.buildRecentWorkouts(modelContainer: modelContainer)

            var context = CoachContext(
                userSummary: userSummary,
                activeInsights: activeInsights,
                derivedMetricsSummary: derivedMetricsSummary,
                ragSummaries: ragSummaries,
                recentWorkouts: recentWorkouts
            )
            context.prepareForModelInput(query: query)
            Log.coach.info(
                "context built rag=\(ragSummaries.count, privacy: .public) insights=\(activeInsights.count, privacy: .public) promptChars=\(context.assembledPrompt(query: query).count, privacy: .public)"
            )
            return context
        }
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
    private static func formatDerivedMetrics(snapshot: DerivedMetricsSnapshot) -> String {
        var lines: [String] = []

        if let acwr = snapshot.acwr {
            let acwrText = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), acwr.acwr)
            lines.append("ACWR: \(acwrText) (\(acwr.zone.badgeLabel)).")
        } else {
            lines.append("ACWR: unavailable.")
        }

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

        if let protein = snapshot.proteinTarget,
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

        return lines.joined(separator: " ")
    }

    @MainActor
    private static func buildRecentWorkouts(modelContainer: ModelContainer) -> [String] {
        let context = ModelContext(modelContainer)
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            ?? .distantPast
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startTime >= twoWeeksAgo },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let sessions = (try? context.fetch(descriptor)) ?? []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return sessions.map { session in
            let dateLabel = formatter.string(from: session.date)
            let exerciseLines = topExercises(for: session, limit: 3)
            if exerciseLines.isEmpty {
                return "\(dateLabel) — \(session.title): (no logged sets)"
            }
            return "\(dateLabel) — \(session.title): \(exerciseLines.joined(separator: "; "))"
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
