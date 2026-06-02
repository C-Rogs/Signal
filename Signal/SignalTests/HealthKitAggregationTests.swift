import Foundation
import Testing
@testable import Signal

struct HealthKitAggregationTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func hrvMeanMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addHRV(value: 40, startDate: day.addingTimeInterval(3600))
        state.addHRV(value: 60, startDate: day.addingTimeInterval(7200))

        let metric = state.mergedMetric(for: day)
        #expect(metric?.hrvSDNN_ms == 50)
    }

    @Test func activeEnergySumMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addActiveEnergy(kcal: 10, startDate: day)
        state.addActiveEnergy(kcal: 5.5, startDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.activeEnergy_kcal == 15.5)
    }

    @Test func bodyMassLatestMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBodyMass(kg: 77, sampleDate: day)
        state.addBodyMass(kg: 78, sampleDate: day.addingTimeInterval(100))

        let metric = state.mergedMetric(for: day)
        #expect(metric?.bodyMassKg == 78)
    }

    @Test func stepCountSumMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addStepCount(count: 200, startDate: day)
        state.addStepCount(count: 300, startDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.stepCount == 500)
    }

    @Test func standHourCountMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addAppleStandHour(stood: true, startDate: day)
        state.addAppleStandHour(stood: true, startDate: day)
        let metric = state.mergedMetric(for: day)
        #expect(metric?.appleStandHours == 2)
    }

    @Test func nutritionSumMatchesXMLRules() {
        let state = DailyNutritionAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addDietaryEnergy(kcal: 200, startDate: day)
        state.addCarbs(g: 40, startDate: day)
        let nutrition = state.mergedNutrition(for: day)
        #expect(nutrition?.dietaryEnergyKcal == 200)
        #expect(nutrition?.carbsG == 40)
    }

    @Test func bloodPressureLatestMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBloodPressure(systolic: 118, diastolic: 76, sampleDate: day)
        state.addBloodPressure(systolic: 122, diastolic: 78, sampleDate: day.addingTimeInterval(60))
        let metric = state.mergedMetric(for: day)
        #expect(metric?.bloodPressureSystolic == 122)
        #expect(metric?.bloodPressureDiastolic == 78)
    }

    @Test func sleepVitalFallbackMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBloodOxygenPct(pct: 97, sampleDate: day.addingTimeInterval(100))
        let metric = state.mergedMetric(for: day)
        #expect(metric?.bloodOxygenPct == 97)
    }

    @Test func sleepWakeDayMatchesXMLRules() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let monday = Self.utcDay(2024, 6, 10)
        let tuesday = Self.utcDay(2024, 6, 11)

        state.addSleepInterval(
            start: monday.addingTimeInterval(22 * 3600),
            end: tuesday.addingTimeInterval(7 * 3600),
            isLegacy: false
        )
        state.addSleepInterval(
            start: monday.addingTimeInterval(23 * 3600),
            end: tuesday.addingTimeInterval(6 * 3600),
            isLegacy: true
        )

        let mondayMetric = state.mergedMetric(for: monday)
        let tuesdayMetric = state.mergedMetric(for: tuesday)

        #expect(mondayMetric?.sleepHours == nil)
        #expect(tuesdayMetric?.sleepHours != nil)
        #expect(abs((tuesdayMetric?.sleepHours ?? 0) - 9.0) < 0.01)
    }

    private static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return utcCalendar.date(from: components)!
    }
}
