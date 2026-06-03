import Foundation
import SwiftData
import Testing
@testable import Signal

// MARK: - Shared fixtures

private enum PipelineGapFixtures {
    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    static let csvHeader =
        "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\"," +
        "\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\"," +
        "\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\"\n"

    /// Returns a Hevy "d MMM yyyy, HH:mm" date string in UTC.
    static func hevyDateString(year: Int, month: Int, day: Int, hour: Int = 10, minute: Int = 0) -> String {
        let months = [
            1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun",
            7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec",
        ]
        let monthName = months[month]!
        return String(format: "%d %@ %d, %02d:%02d", day, monthName, year, hour, minute)
    }

    static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Minimal CSV with one set. Pass an empty string for endStr to simulate a blank end_time cell.
    static func minimalCSV(
        title: String,
        startStr: String,
        endStr: String,
        exerciseTitle: String = "Ab Crunch Machine",
        weightKg: Double = 50,
        reps: Int = 15
    ) -> String {
        csvHeader +
            "\"\(title)\",\"\(startStr)\",\"\(endStr)\",\"\"," +
            "\"\(exerciseTitle)\",\"\",\"\",0,\"normal\"," +
            "\(weightKg),\(reps),,,\n"
    }

    /// Builds a HevyParsedSession with a single exercise and one set.
    static func parsedSession(
        title: String,
        dayStart: Date,
        endTime: Date?,
        exerciseTitle: String = "Ab Crunch Machine"
    ) -> HevyParsedSession {
        let set = HevyParsedSet(
            setIndex: 0,
            setType: "normal",
            weightKg: 50,
            reps: 15,
            distanceKm: nil,
            durationSeconds: nil,
            rpe: nil
        )
        let exercise = HevyParsedExercise(
            exerciseTitle: exerciseTitle,
            notes: nil,
            supersetId: nil,
            order: 0,
            sets: [set]
        )
        return HevyParsedSession(
            title: title,
            sessionDescription: nil,
            startTime: dayStart.addingTimeInterval(3600),
            endTime: endTime,
            dayStart: dayStart,
            exercises: [exercise]
        )
    }
}

private let gapCal = PipelineGapFixtures.utcCalendar

// MARK: - 1. HevyCSVImporter integration

/// Tests that HevyCSVParser and WorkoutStore correctly persist today's session.
/// Key invariant: WorkoutSession.endTime must be non-nil for effort/HR attribution;
/// buildRecentWorkouts surfaces sessions from the last 14 days by startTime.
@MainActor
struct HevyImportTodaySessionTests {
    @Test("CSV with valid end_time creates WorkoutSession with non-nil endTime, correct exercises and sets")
    func importWithValidEndTimeCreatesSession() throws {
        let start = PipelineGapFixtures.hevyDateString(year: 2026, month: 6, day: 3, hour: 9, minute: 0)
        let end   = PipelineGapFixtures.hevyDateString(year: 2026, month: 6, day: 3, hour: 10, minute: 0)
        let csv   = PipelineGapFixtures.minimalCSV(title: "Ab Day", startStr: start, endStr: end)

        let result = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: gapCal)
        #expect(result.sessions.count == 1)
        let session = result.sessions[0]
        #expect(session.title == "Ab Day")
        #expect(session.endTime != nil, "endTime must be non-nil when end_time column is present and non-empty")
        #expect(session.exercises.count == 1)
        #expect(session.exercises[0].sets.count == 1)

        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let counts = try WorkoutStore.upsert(
            parsedSessions: result.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        #expect(counts.sessionCount == 1)
        #expect(counts.exerciseCount == 1)
        #expect(counts.setCount == 1)

        let dayStart = PipelineGapFixtures.utcDay(2026, 6, 3)
        let fetched = try WorkoutStore.fetchSessions(
            for: dayStart,
            source: HevyCSVImporter.importSource,
            in: context
        )
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Ab Day")
        #expect(fetched[0].endTime != nil)
        #expect(fetched[0].exercises.count == 1)
        #expect(fetched[0].exercises[0].exerciseTitle == "Ab Crunch Machine")
        #expect(fetched[0].exercises[0].sets.count == 1)
    }

    @Test("CSV with blank end_time cells applies 60-minute endTime fallback and is visible to coach query")
    func importWithBlankEndTimeAppliesFallbackEndTime() throws {
        let start = PipelineGapFixtures.hevyDateString(year: 2026, month: 6, day: 3, hour: 9, minute: 0)
        let csv   = PipelineGapFixtures.minimalCSV(title: "Ab Day", startStr: start, endStr: "")

        let result = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: gapCal)
        let session = result.sessions[0]
        #expect(session.endTime != nil, "Parser must fall back when end_time cells are blank")
        #expect(
            session.endTime == session.startTime.addingTimeInterval(3600),
            "Fallback endTime must be startTime + 60 minutes"
        )

        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        _ = try WorkoutStore.upsert(
            parsedSessions: result.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )

        let dayStart = PipelineGapFixtures.utcDay(2026, 6, 3)
        let fetched = try WorkoutStore.fetchSessions(
            for: dayStart,
            source: HevyCSVImporter.importSource,
            in: context
        )
        #expect(fetched.count == 1)
        #expect(fetched[0].endTime != nil)

        let twoWeeksAgo = gapCal.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startTime >= twoWeeksAgo },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let visibleToCoach = try context.fetch(descriptor)
        #expect(
            visibleToCoach.contains { $0.title == "Ab Day" },
            "Recent session must appear in buildRecentWorkouts date-range query"
        )
    }
}

// MARK: - 2. CoachContextBuilder.recentWorkouts surface

@MainActor
struct CoachContextBuilderRecentWorkoutsTests {
    @Test("recentWorkouts includes today's session when endTime is non-nil")
    func recentWorkoutsIncludesTodaySessionWithEndTime() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let today = gapCal.startOfDay(for: Date())

        // Import via WorkoutStore so relationships are correctly wired
        let parsed = PipelineGapFixtures.parsedSession(
            title: "Ab Crunch Day",
            dayStart: today,
            endTime: today.addingTimeInterval(7200)
        )
        try await MainActor.run {
            let context = ModelContext(container)
            _ = try WorkoutStore.upsert(
                parsedSessions: [parsed],
                source: HevyCSVImporter.importSource,
                in: context
            )
        }

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "Tell me about today's workout",
            modelContainer: container
        )
        let workoutLines = built.recentWorkouts.joined(separator: "\n")
        #expect(
            workoutLines.contains("Ab Crunch Day"),
            "recentWorkouts must contain today's session when endTime != nil. Got: \(workoutLines)"
        )
    }

    @Test("recentWorkouts includes session imported from CSV with blank end_time")
    func recentWorkoutsIncludesSessionWithBlankEndTimeCSV() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let today = gapCal.startOfDay(for: Date())

        // Parse session from a CSV with blank end_time
        let start = PipelineGapFixtures.hevyDateString(
            year: gapCal.component(.year, from: today),
            month: gapCal.component(.month, from: today),
            day: gapCal.component(.day, from: today),
            hour: 9, minute: 0
        )
        let csv = PipelineGapFixtures.minimalCSV(
            title: "Ab Crunch Day",
            startStr: start,
            endStr: ""  // blank → nil endTime
        )
        let parseResult = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: gapCal)
        try await MainActor.run {
            let context = ModelContext(container)
            _ = try WorkoutStore.upsert(
                parsedSessions: parseResult.sessions,
                source: HevyCSVImporter.importSource,
                in: context
            )
        }

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let built = try await CoachContextBuilder().buildContext(
            for: "Tell me about today's workout",
            modelContainer: container
        )
        let workoutLines = built.recentWorkouts.joined(separator: "\n")
        #expect(
            workoutLines.contains("Ab Crunch Day"),
            "recentWorkouts must include today's session when end_time was blank in CSV. Got: \(workoutLines)"
        )
    }
}

// MARK: - 3. RAG recency: today's workout vector is retrievable

@MainActor
struct RAGRecencyAfterHevyImportTests {
    @Test("Embedding pipeline writes today's HealthVector containing workout content")
    func embeddingPipelineUpsertsTodayVectorWithWorkoutContent() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let today = gapCal.startOfDay(for: Date())

        // Persist session and DailyMetric stub for today
        let parsed = PipelineGapFixtures.parsedSession(
            title: "Ab Day",
            dayStart: today,
            endTime: today.addingTimeInterval(7200)
        )
        try await MainActor.run {
            let context = ModelContext(container)
            _ = try WorkoutStore.upsert(
                parsedSessions: [parsed],
                source: HevyCSVImporter.importSource,
                in: context
            )
            try DailyMetricStore.ensureDayExists(
                date: today,
                source: HevyCSVImporter.importSource,
                in: context
            )
            try context.save()
        }

        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let service = DeterministicTestEmbeddingService.shared
        let vectorsWritten = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: [today],
            modelContainer: container,
            calendar: gapCal,
            embeddingService: service,
            workoutSource: HevyCSVImporter.importSource,
            embedBatchSize: 1,
            onVectorsWritten: { _ in }
        )
        // Note: if this fails with 0 on simulator, EmbeddingRunPolicy.mayUseMetal returned false
        // (UIApplication.applicationState != .active). That is a second gap to fix.
        #expect(vectorsWritten >= 1, "At least one vector must be written for today")

        let todayKey = Summarizer.dayKey(for: today, calendar: gapCal)
        let vectors = try await MainActor.run {
            try ModelContext(container).fetch(FetchDescriptor<HealthVector>())
        }
        let todayVector = vectors.first { $0.dayKey == todayKey }
        #expect(todayVector != nil, "HealthVector for today's dayKey '\(todayKey)' must exist")
        if let tv = todayVector {
            let hasWorkoutContent =
                tv.summaryText.contains("Ab Crunch Machine") ||
                tv.summaryText.contains("Ab Day") ||
                tv.summaryText.contains("Hevy workouts")
            #expect(
                hasWorkoutContent,
                "Vector summaryText must include workout content. Got: \(tv.summaryText)"
            )
        }
    }

    @Test("RAG retriever returns today's workout-containing vector first with recency boost")
    func ragRetrievalRanksWorkoutDayFirstForWorkoutQuery() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)

        let today = gapCal.startOfDay(for: Date())
        let todayKey = Summarizer.dayKey(for: today, calendar: gapCal)

        let queryText = "ab crunch machine workout today"
        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let workoutVector = try await DeterministicTestEmbeddingService.shared.embed(
            queryText,
            kind: .query
        )

        let oldDate = gapCal.date(byAdding: .day, value: -90, to: today)!
        let oldKey = Summarizer.dayKey(for: oldDate, calendar: gapCal)

        try store.insert(
            dayKey: oldKey,
            metricKind: DailyMetricStore.dailyVectorKind,
            summaryText: "Health day \(oldKey). Sleep 7 hours.",
            vector: workoutVector
        )
        try store.insert(
            dayKey: todayKey,
            metricKind: DailyMetricStore.dailyVectorKind,
            summaryText: "Health day \(todayKey). Hevy workouts: Ab Day: Ab Crunch Machine: 3 x 15 @ 50kg.",
            vector: workoutVector
        )

        let results = try await RAGRetriever.retrieve(
            query: queryText,
            k: 2,
            boostDaysWithin: 30,
            modelContainer: container
        )
        #expect(results.count == 2, "Both vectors should be retrieved")
        #expect(
            results.first?.contains("Ab Day") == true || results.first?.contains(todayKey) == true,
            "Today's workout vector must rank first due to recency boost. Got: \(results)"
        )
    }
}

// MARK: - 4. Pipeline completeness: full in-memory run for today

@MainActor
struct HevyImportPipelineCompletenessTests {
    @Test("parse → persist → ensureDayExists → embedAndUpsert writes vector containing today's workout")
    func fullPipelineForTodayCreatesVectorWithWorkoutContent() async throws {
        let today = gapCal.startOfDay(for: Date())
        let year  = gapCal.component(.year, from: today)
        let month = gapCal.component(.month, from: today)
        let day   = gapCal.component(.day, from: today)

        let start = PipelineGapFixtures.hevyDateString(year: year, month: month, day: day, hour: 9, minute: 0)
        let end   = PipelineGapFixtures.hevyDateString(year: year, month: month, day: day, hour: 10, minute: 0)
        let csv   = PipelineGapFixtures.minimalCSV(
            title: "Ab Day",
            startStr: start,
            endStr: end,
            exerciseTitle: "Ab Crunch Machine"
        )

        // Step 1: parse
        let parseResult = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: gapCal)
        #expect(parseResult.sessions.count == 1)
        #expect(parseResult.affectedDayStarts.count == 1)
        #expect(
            parseResult.affectedDayStarts[0] == today,
            "Affected day must be today. Got \(parseResult.affectedDayStarts[0]), expected \(today)"
        )

        let container = try SignalModelContainer.make(inMemoryOnly: true)

        // Step 2: persist WorkoutSession rows
        let counts = try await MainActor.run {
            let context = ModelContext(container)
            try WorkoutStore.wipeLossyHevyDataIfNeeded(
                source: HevyCSVImporter.importSource,
                in: context
            )
            return try WorkoutStore.upsert(
                parsedSessions: parseResult.sessions,
                source: HevyCSVImporter.importSource,
                in: context
            )
        }
        #expect(counts.sessionCount == 1)
        #expect(counts.setCount == 1)

        // Step 3: ensure DailyMetric stub exists
        try await MainActor.run {
            let context = ModelContext(container)
            try DailyMetricStore.ensureDayExists(
                date: today,
                source: HevyCSVImporter.importSource,
                in: context
            )
            try context.save()
        }
        let metricCount = try await MainActor.run {
            try DailyMetricStore.count(in: ModelContext(container))
        }
        #expect(metricCount >= 1, "DailyMetric stub must exist for today")

        // Step 4: run embedding pipeline
        EmbeddingBackend.useDeterministicTestEmbedding = true
        defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

        let service = DeterministicTestEmbeddingService.shared
        let vectorsWritten = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: parseResult.affectedDayStarts,
            modelContainer: container,
            calendar: gapCal,
            embeddingService: service,
            workoutSource: HevyCSVImporter.importSource,
            embedBatchSize: 1,
            onVectorsWritten: { _ in }
        )
        #expect(vectorsWritten >= 1, "Pipeline must write at least one vector for today")

        // Step 5: confirm HealthVector for today contains workout
        let todayKey = Summarizer.dayKey(for: today, calendar: gapCal)
        let vectors = try await MainActor.run {
            try ModelContext(container).fetch(FetchDescriptor<HealthVector>())
        }
        let todayVec = vectors.first { $0.dayKey == todayKey }
        #expect(todayVec != nil, "HealthVector for dayKey '\(todayKey)' must exist after pipeline")
        if let tv = todayVec {
            let hasWorkout =
                tv.summaryText.contains("Ab Crunch Machine") ||
                tv.summaryText.contains("Ab Day") ||
                tv.summaryText.contains("Hevy workouts")
            #expect(hasWorkout, "Vector must include workout content. Got: \(tv.summaryText)")
        }

        // Step 6: confirm session is visible to buildRecentWorkouts (14-day startTime filter)
        let visibleSessions = try await MainActor.run { () throws -> [WorkoutSession] in
            let twoWeeksAgo = gapCal.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
            var descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.startTime >= twoWeeksAgo },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            descriptor.fetchLimit = 2
            return try ModelContext(container).fetch(descriptor)
        }
        #expect(
            visibleSessions.contains { $0.title == "Ab Day" },
            "Today's session must be visible to buildRecentWorkouts; check end_time parsing if this fails."
        )
    }

    @Test("Blank end_time in CSV still surfaces session in buildRecentWorkouts query after fallback")
    func blankEndTimeInCSVVisibleToCoach() async throws {
        let today = gapCal.startOfDay(for: Date())
        let year  = gapCal.component(.year, from: today)
        let month = gapCal.component(.month, from: today)
        let day   = gapCal.component(.day, from: today)

        let start = PipelineGapFixtures.hevyDateString(year: year, month: month, day: day, hour: 9, minute: 0)
        let csv   = PipelineGapFixtures.minimalCSV(
            title: "Ab Day",
            startStr: start,
            endStr: ""  // blank end_time
        )

        let parseResult = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: gapCal)
        let container = try SignalModelContainer.make(inMemoryOnly: true)

        try await MainActor.run {
            let context = ModelContext(container)
            _ = try WorkoutStore.upsert(
                parsedSessions: parseResult.sessions,
                source: HevyCSVImporter.importSource,
                in: context
            )
        }

        let visibleSessions = try await MainActor.run { () throws -> [WorkoutSession] in
            let twoWeeksAgo = gapCal.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
            var descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.startTime >= twoWeeksAgo },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            descriptor.fetchLimit = 2
            return try ModelContext(container).fetch(descriptor)
        }
        #expect(
            visibleSessions.contains { $0.title == "Ab Day" },
            "Session with blank end_time must be visible after parser fallback endTime"
        )
    }
}
