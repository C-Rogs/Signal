import Foundation
import Testing
@testable import Signal

private enum SummarizerTestFixtures {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func utcDay(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return utcCalendar.date(from: components)!
    }
}

@MainActor
struct SummarizerTests {
    @Test func dailyMetricRoundTripsToDailySummaryJSON() throws {
        let metric = DailyMetric(
            date: SummarizerTestFixtures.utcDay(year: 2024, month: 6, day: 15),
            hrvSDNN_ms: 48.5,
            restingHR: 54,
            activeEnergy_kcal: 450,
            sleepHours: 7.25,
            source: "unit-test"
        )

        let (summary, _) = Summarizer.summarize(metric: metric, calendar: SummarizerTestFixtures.utcCalendar)
        #expect(summary.date == "2024-06-15")
        #expect(summary.hrvSDNN == 48.5)
        #expect(summary.restingHR == 54)
        #expect(summary.activeEnergy == 450)
        #expect(summary.sleepHours == 7.25)
        #expect(summary.workoutsSummary == nil)
        #expect(summary.recoveryScore == nil)

        let data = try Summarizer.encodeJSON(summary)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == """
{"activeEnergy":450,"date":"2024-06-15","hrvSDNN":48.5,"restingHR":54,"sleepHours":7.25}
""")

        let decoded = try Summarizer.decodeJSON(data)
        #expect(decoded == summary)
    }

    @Test func embeddingTextSnapshotIsStable() {
        let metric = DailyMetric(
            date: SummarizerTestFixtures.utcDay(year: 2024, month: 6, day: 15),
            hrvSDNN_ms: 48.5,
            restingHR: 54,
            activeEnergy_kcal: 450,
            sleepHours: 7.25,
            source: "unit-test"
        )

        let (_, text) = Summarizer.summarize(
            metric: metric,
            workoutSummaries: ["Leg day: back squat 5x5 at 140 kg"],
            calendar: SummarizerTestFixtures.utcCalendar
        )

        #expect(text == """
Health day 2024-06-15. HRV SDNN 48.5 ms. Resting HR 54 bpm. Sleep 7.25 hours. Active energy 450 kcal. Hevy workouts: Leg day: back squat 5x5 at 140 kg.
""")
    }

    @Test func nutritionOnlyDayProducesNonEmptySummary() {
        let day = SummarizerTestFixtures.utcDay(year: 2024, month: 7, day: 1)
        let nutrition = DailyNutrition(
            date: day,
            dietaryEnergyKcal: 2100,
            proteinG: 140,
            source: "unit-test"
        )
        let (_, text) = Summarizer.summarize(
            day: day,
            metric: nil,
            nutrition: nutrition,
            calendar: SummarizerTestFixtures.utcCalendar
        )
        #expect(text.contains("Health day 2024-07-01."))
        #expect(text.contains("Nutrition:"))
        #expect(text.contains("2100 kcal"))
    }

    @Test func embeddingTextIncludesExpandedMetricExpansionFields() {
        let day = SummarizerTestFixtures.utcDay(year: 2024, month: 8, day: 20)
        let metric = DailyMetric(
            date: day,
            hrvSDNN_ms: 52,
            restingHR: 53,
            activeEnergy_kcal: 520,
            sleepHours: 7.5,
            bodyMassKg: 78.2,
            vo2Max: 48.5,
            respiratoryRate: 14.2,
            wristTemperatureDeltaC: 0.3,
            bloodOxygenPct: 97.5,
            bodyFatPercentage: 14,
            leanBodyMassKg: 67.1,
            bloodPressureSystolic: 118,
            bloodPressureDiastolic: 76,
            source: "unit-test"
        )
        let nutrition = DailyNutrition(
            date: day,
            dietaryEnergyKcal: 2100,
            proteinG: 140,
            carbsG: 220,
            fatTotalG: 70,
            source: "unit-test"
        )
        let appleWorkout = AppleWorkout(
            stableID: "unit-run",
            activityType: "Running",
            startDate: day.addingTimeInterval(3600),
            endDate: day.addingTimeInterval(7200),
            durationSec: 3600,
            activeEnergyKcal: 480,
            distanceKm: 10.2,
            source: "unit-test"
        )
        let (_, text) = Summarizer.summarize(
            day: day,
            metric: metric,
            nutrition: nutrition,
            workoutSummaries: ["Leg day: back squat 5x5 at 140 kg"],
            appleWorkouts: [appleWorkout],
            calendar: SummarizerTestFixtures.utcCalendar
        )

        #expect(text == """
Health day 2024-08-20. HRV SDNN 52.0 ms. Resting HR 53 bpm. Sleep 7.50 hours. Sleep respiratory rate 14.2 brpm. Sleep wrist temperature delta 0.30 C. Sleep blood oxygen 97.5 pct. Active energy 520 kcal. Body mass 78.2 kg. Body fat 14.0 pct. Lean mass 67.1 kg. VO2 max 48.5 ml/kg/min. Nutrition: 2100 kcal, 140 g protein, 220 g carbs, 70 g fat. Blood pressure 118/76 mmHg. Hevy workouts: Leg day: back squat 5x5 at 140 kg. Apple workouts: Running 60 min, 480 kcal, 10.20 km.
""")
    }

    @Test func workoutOnlyDayProducesNonEmptySummary() {
        let day = SummarizerTestFixtures.utcDay(year: 2024, month: 7, day: 2)
        let workout = AppleWorkout(
            stableID: "unit-run",
            activityType: "Running",
            startDate: day.addingTimeInterval(3600),
            endDate: day.addingTimeInterval(7200),
            durationSec: 3600,
            distanceKm: 10,
            source: "unit-test"
        )
        let (_, text) = Summarizer.summarize(
            day: day,
            metric: nil,
            appleWorkouts: [workout],
            calendar: SummarizerTestFixtures.utcCalendar
        )
        #expect(text.contains("Apple workouts:"))
        #expect(text.contains("Running"))
    }

    @Test func missingMetricsProduceCleanSummary() throws {
        let metric = DailyMetric(
            date: SummarizerTestFixtures.utcDay(year: 2024, month: 1, day: 2),
            hrvSDNN_ms: 41,
            source: "unit-test"
        )

        let (summary, text) = Summarizer.summarize(metric: metric, calendar: SummarizerTestFixtures.utcCalendar)
        let data = try Summarizer.encodeJSON(summary)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json == """
{"date":"2024-01-02","hrvSDNN":41}
""")
        #expect(text == "Health day 2024-01-02. HRV SDNN 41.0 ms.")
        #expect(!text.contains("nil"))
        #expect(!text.contains("0 kcal"))
        #expect(!text.contains("0 bpm"))
        #expect(!text.contains("Sleep 0"))
    }
}
