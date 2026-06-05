import SwiftData
import XCTest
@testable import Signal

final class CoachContextBuilderTests: XCTestCase {
    func testAssembledPromptWithinBudgetWithRealisticData() {
        var context = CoachContext(
            userSummary: "You, goal: Hypertrophy, 4 days/week, target RIR 2.",
            activeInsights: (1 ... 3).map { "• Insight \($0): volume trending high for chest." },
            derivedMetricsSummary: String(repeating: "ACWR 1.1 (Optimal). Volume chest 12 sets. ", count: 12),
            ragSummaries: (1 ... 4).map { "2026-05-\($0 + 10): HRV 65 ms, sleep 7.2 h, 14 working sets." },
            recentWorkouts: [
                "Jun 1, Push: Bench 100kg×5; OHP 60kg×8",
                "May 30, Pull: Row 90kg×6; Pulldown 70kg×10",
            ]
        )
        context.prepareForModelInput(query: "Should I add sets for chest this week?")
        let prompt = context.assembledPrompt(query: "Should I add sets for chest this week?")
        XCTAssertLessThanOrEqual(prompt.count, CoachContext.assembledPromptMaxChars)
    }

    func testTruncationDropsRAGBeforeUserSummaryAndInsights() {
        let longRAG = (1 ... 20).map { "Day \($0): " + String(repeating: "x", count: 200) }
        var context = CoachContext(
            userSummary: "You, goal: Strength, 3 days/week, target RIR 1.",
            activeInsights: ["• Keep protein up."],
            derivedMetricsSummary: "ACWR: 0.95 (Optimal).",
            ragSummaries: longRAG,
            recentWorkouts: ["Jun 1, Legs: Squat 140kg×5"],
            calendarSummary: "Tomorrow: Team sync 10:00 AM."
        )
        let userBefore = context.userSummary
        let insightsBefore = context.activeInsights
        let calendarBefore = context.calendarSummary
        context.prepareForModelInput(query: "What is on my calendar tomorrow?")
        XCTAssertLessThan(context.ragSummaries.count, longRAG.count)
        XCTAssertEqual(context.userSummary, userBefore)
        XCTAssertEqual(context.activeInsights, insightsBefore)
        XCTAssertEqual(context.calendarSummary, calendarBefore)
    }

    func testScheduleIntentDetection() {
        XCTAssertTrue(CoachQueryIntent.isScheduleFocused("What's in my calendar tomorrow?"))
        XCTAssertFalse(CoachQueryIntent.isScheduleFocused("How did bench press progress this month?"))
    }

    func testExerciseHistoryIntentDetection() {
        XCTAssertTrue(CoachQueryIntent.isExerciseHistoryFocused("How has my bench press progressed?"))
        XCTAssertFalse(CoachQueryIntent.isExerciseHistoryFocused("How is my recovery today?"))
    }

    func testOffTopicIntentDetection() {
        XCTAssertTrue(CoachQueryIntent.isOffTopic("Who will win the next election?"))
        XCTAssertFalse(CoachQueryIntent.isOffTopic("Should I train legs today?"))
    }

    @MainActor
    func testNonScheduleQueryOmitsCalendarSection() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "How is my ACWR?",
            modelContainer: container
        )
        let prompt = built.assembledPrompt(query: "How is my ACWR?")
        XCTAssertFalse(prompt.contains("## Schedule"))
    }

    @MainActor
    func testStaleHealthSyncAddsFreshnessLine() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let calendar = SchedulingCalendar.make()
        let staleDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: Date())))
        context.insert(
            DailyMetric(
                date: staleDay,
                hrvSDNN_ms: 50,
                source: "test"
            )
        )
        try context.save()

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }
        await DerivedMetricsService.shared.invalidateCache()

        let built = try await CoachContextBuilder().buildContext(
            for: "How is recovery?",
            modelContainer: container
        )
        XCTAssertTrue(built.derivedMetricsSummary.contains("Health sync latest:"))
    }

    @MainActor
    func testProteinLineOmitsWhenOnlyOldNutritionLogged() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let profile = UserProfile()
        profile.bodyweightKg = 80
        context.insert(profile)
        let calendar = SchedulingCalendar.make()
        let oldDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: calendar.startOfDay(for: Date())))
        context.insert(DailyNutrition(date: oldDay, proteinG: 50, source: "test"))
        try context.save()

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }
        await DerivedMetricsService.shared.invalidateCache()

        let built = try await CoachContextBuilder().buildContext(
            for: "Volume check",
            modelContainer: container
        )
        XCTAssertFalse(built.derivedMetricsSummary.contains("Protein:"))
    }

    @MainActor
    func testUserSummaryOmitsNilLiteral() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let modelContext = ModelContext(container)
        _ = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: modelContext)

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "How is my volume?",
            modelContainer: container
        )
        XCTAssertFalse(built.userSummary.contains("nil"))
        XCTAssertTrue(built.userSummary.contains("You,"))
    }

    @MainActor
    func testWorkoutPrescriptionOmitsProteinInMetrics() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let modelContext = ModelContext(container)
        let profile = UserProfile()
        profile.bodyweightKg = 80
        modelContext.insert(profile)
        let calendar = SchedulingCalendar.make()
        let today = calendar.startOfDay(for: Date())
        modelContext.insert(DailyNutrition(date: today, proteinG: 50, source: "test"))
        try modelContext.save()

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }
        await DerivedMetricsService.shared.invalidateCache()

        let built = try await CoachContextBuilder().buildContext(
            for: "What should I train today?",
            modelContainer: container
        )
        XCTAssertFalse(built.derivedMetricsSummary.contains("Protein:"))
        XCTAssertTrue(built.derivedMetricsSummary.contains("ACWR"))
    }

    @MainActor
    func testNutritionQueryOmitsACWRAndWorkouts() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "Am I hitting protein?",
            modelContainer: container
        )
        let prompt = built.assembledPrompt(query: "Am I hitting protein?")
        XCTAssertFalse(built.derivedMetricsSummary.contains("ACWR"))
        XCTAssertFalse(built.derivedMetricsSummary.contains("Volume this week"))
        XCTAssertFalse(prompt.contains("## Recent workouts"))
    }

    @MainActor
    func testNutritionQueryShowsProteinStatusEvenOnTarget() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let modelContext = ModelContext(container)
        let profile = UserProfile()
        profile.bodyweightKg = 80
        modelContext.insert(profile)
        let calendar = SchedulingCalendar.make()
        let today = calendar.startOfDay(for: Date())
        modelContext.insert(DailyNutrition(date: today, proteinG: 170, source: "test"))
        try modelContext.save()

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }
        await DerivedMetricsService.shared.invalidateCache()

        let built = try await CoachContextBuilder().buildContext(
            for: "Did I hit my protein target today?",
            modelContainer: container
        )
        XCTAssertTrue(built.derivedMetricsSummary.contains("Protein:"))
        XCTAssertTrue(
            built.derivedMetricsSummary.contains("on track")
                || built.derivedMetricsSummary.contains("below target")
        )
        XCTAssertFalse(built.derivedMetricsSummary.contains("ACWR"))
    }

    @MainActor
    func testActiveInsightsCappedAtThree() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let modelContext = ModelContext(container)
        let now = Date()
        for index in 0 ..< 6 {
            modelContext.insert(
                Insight(
                    dedupeKey: "test.cap.\(index)",
                    type: .volumeAboveMRV,
                    severity: index % 2 == 0 ? .alert : .warning,
                    bodyText: "Body \(index)",
                    createdAt: now.addingTimeInterval(TimeInterval(-index)),
                    expiresAt: now.addingTimeInterval(86400)
                )
            )
        }
        try modelContext.save()

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "Any concerns?",
            modelContainer: container
        )
        XCTAssertEqual(built.activeInsights.count, 3)
    }
}
