import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct HevyCSVImporterTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let csvHeader = "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\"\n"

    @Test func csvParserHandlesQuotedCommasAndNewlines() throws {
        let csv = Self.csvHeader + """
"Leg Day","1 Jun 2024, 10:00","1 Jun 2024, 11:00","","Squat","","",0,"normal",140,5,,,
"Notes, rest day","1 Jun 2024, 10:05","1 Jun 2024, 11:05","","Squat","","",0,"normal",100,8,,,
"""
        let result = try HevyCSVParser.parse(
            data: Data(csv.utf8),
            calendar: Self.utcCalendar
        )
        #expect(result.rowsParsed == 2)
        #expect(result.sessions.count == 2)
        #expect(result.sessions.contains { $0.title == "Notes, rest day" })
    }

    @Test func groupsSetsIntoSessionsAndDays() throws {
        let csv = Self.csvHeader + """
"Push A","10 Jun 2024, 09:00","10 Jun 2024, 10:00","","Bench Press (Barbell)","","",0,"normal",61.2,8,,,
"Push A","10 Jun 2024, 09:00","10 Jun 2024, 10:00","","Bench Press (Barbell)","","",1,"normal",70.3,5,,,
"Pull B","11 Jun 2024, 18:00","11 Jun 2024, 19:00","","Lat Pulldown","","",0,"normal",54.4,10,,,
"""
        let result = try HevyCSVParser.parse(
            data: Data(csv.utf8),
            calendar: Self.utcCalendar
        )

        #expect(result.rowsParsed == 3)
        #expect(result.sessions.count == 2)
        #expect(result.affectedDayStarts.count == 2)

        let pushSession = result.sessions.first { $0.title == "Push A" }
        #expect(pushSession?.exercises.count == 1)
        #expect(pushSession?.exercises[0].sets.count == 2)
    }

    @Test func threeSetRPEExampleRoundTripsAndRendersFaithfully() throws {
        let csv = Self.csvHeader + """
"Upper","31 May 2026, 17:53","31 May 2026, 18:53","","Seated Incline Curl (Dumbbell)","","",0,"normal",24,10,,,8
"Upper","31 May 2026, 17:53","31 May 2026, 18:53","","Seated Incline Curl (Dumbbell)","","",1,"normal",24,10,,,8.5
"Upper","31 May 2026, 17:53","31 May 2026, 18:53","","Seated Incline Curl (Dumbbell)","","",2,"normal",24,10,,,9
"""
        let parseResult = try HevyCSVParser.parse(
            data: Data(csv.utf8),
            calendar: Self.utcCalendar
        )
        #expect(parseResult.rowsParsed == 3)
        let exercise = parseResult.sessions[0].exercises[0]
        #expect(exercise.sets.count == 3)

        let rendered = Summarizer.renderExerciseSummary(parsed: exercise)
        #expect(rendered.contains("3 x 10 @ 24kg"))
        #expect(rendered.contains("RPE 8 to 9"))

        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let counts = try WorkoutStore.upsert(
            parsedSessions: parseResult.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        #expect(counts.setCount == 3)

        let reimport = try WorkoutStore.upsert(
            parsedSessions: parseResult.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        let totals = try WorkoutStore.counts(source: HevyCSVImporter.importSource, in: context)
        #expect(totals.sessionCount == 1)
        #expect(totals.setCount == 3)
        #expect(reimport.setCount == 3)
    }

    @Test func daySummaryMentionsWorkoutSession() throws {
        let csv = Self.csvHeader + """
"Push A","10 Jun 2024, 09:00","10 Jun 2024, 10:00","","Bench Press (Barbell)","","",0,"normal",70,5,,,
"""
        let parseResult = try HevyCSVParser.parse(
            data: Data(csv.utf8),
            calendar: Self.utcCalendar
        )
        let day = Self.utcDay(2024, 6, 10)
        let metric = DailyMetric(
            date: day,
            activeEnergy_kcal: 400,
            source: DailyMetricAggregator.importSource
        )
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        _ = try WorkoutStore.upsert(
            parsedSessions: parseResult.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        let sessions = try WorkoutStore.fetchSessions(
            for: day,
            source: HevyCSVImporter.importSource,
            in: context
        )
        let (summary, text) = Summarizer.summarize(
            metric: metric,
            workoutSessions: sessions,
            calendar: Self.utcCalendar
        )

        #expect(summary.workoutsSummary?.contains("Push A") == true)
        #expect(text.contains("Push A"))
        #expect(text.contains("Hevy workouts:"))
    }

    @Test func rejectsMissingRequiredHeaders() {
        let csv = """
"workout","when","lift"
"Push","10 Jun 2024, 09:00","Bench"
"""
        do {
            _ = try HevyCSVParser.parse(data: Data(csv.utf8), calendar: Self.utcCalendar)
            Issue.record("expected unexpectedHeaders error")
        } catch let error as HevyCSVParseError {
            if case .unexpectedHeaders(let found, let missing) = error {
                #expect(found.contains("workout"))
                #expect(missing.contains("title"))
            } else {
                Issue.record("unexpected error \(error)")
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    private static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return utcCalendar.date(from: components)!
    }
}
