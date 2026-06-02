import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct AppleHealthImportAggregationTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func hrvMeanAndEnergySum() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addHRV(value: 40, startDate: day.addingTimeInterval(3600))
        state.addHRV(value: 60, startDate: day.addingTimeInterval(7200))
        state.addActiveEnergy(kcal: 10, startDate: day)
        state.addActiveEnergy(kcal: 5.5, startDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.hrvSDNN_ms == 50)
        #expect(metric?.activeEnergy_kcal == 15.5)
    }

    @Test func restingHRMean() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addRestingHR(value: 50, startDate: day)
        state.addRestingHR(value: 54, startDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.restingHR == 52)
    }

    @Test func sleepWakeDayAndOverlapDedup() {
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

    @Test func legacyAsleepCountedWhenNoGranularOverlap() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addSleepInterval(
            start: day.addingTimeInterval(1 * 3600),
            end: day.addingTimeInterval(8 * 3600),
            isLegacy: true
        )

        let metric = state.mergedMetric(for: day)
        #expect(abs((metric?.sleepHours ?? 0) - 7.0) < 0.01)
    }

    @Test func unitNormalization() {
        #expect(AppleHealthUnitNormalizer.normalizedHRV(value: 48, unit: "ms") == 48)
        #expect(AppleHealthUnitNormalizer.normalizedHRV(value: 48, unit: "bpm") == nil)
        #expect(AppleHealthUnitNormalizer.normalizedRestingHR(value: 54, unit: "count/min") == 54)
        #expect(AppleHealthUnitNormalizer.normalizedActiveEnergyKcal(value: 100, unit: "kcal") == 100)
        let kcal = AppleHealthUnitNormalizer.normalizedActiveEnergyKcal(value: 418.4, unit: "kJ")
        #expect(kcal != nil)
        #expect(abs((kcal ?? 0) - 100) < 0.01)
    }

    @Test func dateParserAcceptsExportFormat() {
        AppleHealthDateParser.resetForTesting()
        let parsed = AppleHealthDateParser.parse("2024-06-15 08:30:00 +0000")
        #expect(parsed != nil)
    }

    @Test func dailyMetricUpsertIsIdempotent() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let day = Self.utcDay(2024, 6, 15)

        let first = DailyMetric(
            date: day,
            hrvSDNN_ms: 40,
            activeEnergy_kcal: 100,
            source: DailyMetricAggregator.importSource
        )
        try DailyMetricStore.upsertBatch([first], in: context)
        #expect(try DailyMetricStore.count(in: context) == 1)

        let second = DailyMetric(
            date: day,
            hrvSDNN_ms: 45,
            activeEnergy_kcal: 200,
            source: DailyMetricAggregator.importSource
        )
        try DailyMetricStore.upsertBatch([second], in: context)
        #expect(try DailyMetricStore.count(in: context) == 1)

        let fetched = try context.fetch(FetchDescriptor<DailyMetric>()).first
        #expect(fetched?.hrvSDNN_ms == 45)
        #expect(fetched?.activeEnergy_kcal == 200)
    }

    @Test func vectorUpsertIsIdempotent() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        let vectorA = VectorStoreTestsHelper.unitVector(axis: 0)
        let vectorB = VectorStoreTestsHelper.unitVector(axis: 1)

        try store.upsert(
            dayKey: "2024-06-15",
            metricKind: DailyMetricStore.dailyVectorKind,
            summaryText: "first",
            vector: vectorA
        )
        try context.save()
        #expect(try store.count() == 1)

        try store.upsert(
            dayKey: "2024-06-15",
            metricKind: DailyMetricStore.dailyVectorKind,
            summaryText: "second",
            vector: vectorB
        )
        try context.save()
        #expect(try store.count() == 1)

        let rows = try context.fetch(FetchDescriptor<HealthVector>())
        #expect(rows.first?.summaryText == "second")
    }

    @Test func bodyMassKeepsLatestSampleThatDay() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBodyMass(kg: 80, sampleDate: day.addingTimeInterval(3600))
        state.addBodyMass(kg: 81, sampleDate: day.addingTimeInterval(7200))
        state.addBodyMass(kg: 79, sampleDate: day.addingTimeInterval(5400))

        let metric = state.mergedMetric(for: day)
        #expect(metric?.bodyMassKg == 81)
    }

    @Test func stepCountAndBasalEnergySum() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addStepCount(count: 1000, startDate: day)
        state.addStepCount(count: 500, startDate: day)
        state.addBasalEnergy(kcal: 1200, startDate: day)
        state.addBasalEnergy(kcal: 300, startDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.stepCount == 1500)
        #expect(metric?.basalEnergyKcal == 1500)
    }

    @Test func heartRateDailyMaxAndMean() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addHeartRate(bpm: 120, sampleDate: day)
        state.addHeartRate(bpm: 80, sampleDate: day)

        let metric = state.mergedMetric(for: day)
        #expect(metric?.heartRateMax == 120)
        #expect(metric?.heartRateAvg == 100)
    }

    @Test func sleepTimeMetricsAverageOnWakeDay() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let wakeDay = Self.utcDay(2024, 6, 11)
        state.addSleepInterval(
            start: wakeDay.addingTimeInterval(-8 * 3600),
            end: wakeDay.addingTimeInterval(3600),
            isLegacy: false
        )
        let duringSleep = wakeDay.addingTimeInterval(-4 * 3600)
        state.addRespiratoryRate(brpm: 14, sampleDate: duringSleep)
        state.addRespiratoryRate(brpm: 16, sampleDate: duringSleep.addingTimeInterval(60))
        state.addBloodOxygenPct(pct: 96, sampleDate: duringSleep)
        state.addBloodOxygenPct(pct: 98, sampleDate: duringSleep.addingTimeInterval(120))

        let metric = state.mergedMetric(for: wakeDay)
        #expect(metric?.respiratoryRate == 15)
        #expect(metric?.bloodOxygenPct == 97)
    }

    @Test func appleWorkoutUpsertIsIdempotent() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let start = Self.utcDay(2024, 6, 10)
        let end = start.addingTimeInterval(3600)
        let first = AppleWorkout(
            stableID: "test-run",
            activityType: "Running",
            startDate: start,
            endDate: end,
            durationSec: 3600,
            activeEnergyKcal: 400,
            distanceKm: 8,
            source: AppleWorkoutStore.exportSource
        )
        try AppleWorkoutStore.upsertBatch([first], in: context)
        #expect(try AppleWorkoutStore.count(in: context) == 1)

        let second = AppleWorkout(
            stableID: "test-run",
            activityType: "Running",
            startDate: start,
            endDate: end,
            durationSec: 3600,
            activeEnergyKcal: 450,
            distanceKm: 9,
            source: AppleWorkoutStore.exportSource
        )
        try AppleWorkoutStore.upsertBatch([second], in: context)
        #expect(try AppleWorkoutStore.count(in: context) == 1)
        let fetched = try context.fetch(FetchDescriptor<AppleWorkout>()).first
        #expect(fetched?.activeEnergyKcal == 450)
        #expect(fetched?.distanceKm == 9)
    }

    @Test func bodyFatNormalizesFractionToPercent() {
        let normalized = AppleHealthUnitNormalizer.normalizedBodyFatPercentage(value: 0.14, unit: "%")
        #expect(abs((normalized ?? 0) - 14) < 0.001)
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBodyFatPercentage(pct: 14, sampleDate: day)
        let metric = state.mergedMetric(for: day)
        #expect(metric?.bodyFatPercentage == 14)
    }

    @Test func nutritionSumsPerDay() {
        let state = DailyNutritionAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addDietaryEnergy(kcal: 100, startDate: day)
        state.addDietaryEnergy(kcal: 50, startDate: day)
        state.addProtein(g: 30, startDate: day)
        let nutrition = state.mergedNutrition(for: day)
        #expect(nutrition?.dietaryEnergyKcal == 150)
        #expect(nutrition?.proteinG == 30)
    }

    @Test func standHourCountsStoodOnly() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addAppleStandHour(stood: true, startDate: day)
        state.addAppleStandHour(stood: true, startDate: day.addingTimeInterval(3600))
        state.addAppleStandHour(stood: false, startDate: day.addingTimeInterval(7200))
        let metric = state.mergedMetric(for: day)
        #expect(metric?.appleStandHours == 2)
    }

    @Test func bloodPressureKeepsLatestPair() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addBloodPressure(systolic: 120, diastolic: 80, sampleDate: day)
        state.addBloodPressure(systolic: 130, diastolic: 85, sampleDate: day.addingTimeInterval(3600))
        let metric = state.mergedMetric(for: day)
        #expect(metric?.bloodPressureSystolic == 130)
        #expect(metric?.bloodPressureDiastolic == 85)
    }

    @Test func sleepVitalCalendarDayFallbackWithoutSleep() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addRespiratoryRate(brpm: 15, sampleDate: day.addingTimeInterval(3600))
        let metric = state.mergedMetric(for: day)
        #expect(metric?.respiratoryRate == 15)
    }

    @Test func physicalEffortMeanOfNonZeroSamples() {
        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let day = Self.utcDay(2024, 6, 10)
        state.addPhysicalEffort(value: 0, startDate: day)
        state.addPhysicalEffort(value: 4, startDate: day)
        state.addPhysicalEffort(value: 6, startDate: day)
        let metric = state.mergedMetric(for: day)
        #expect(metric?.physicalEffort == 5)
    }

    @Test func nutritionOnlyDayEmbedsVector() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Self.utcDay(2024, 8, 1)
        let nutrition = DailyNutrition(
            date: day,
            dietaryEnergyKcal: 1800,
            proteinG: 120,
            source: DailyMetricAggregator.importSource
        )
        try await MainActor.run {
            let context = ModelContext(container)
            try DailyNutritionStore.upsertBatch([nutrition], in: context)
        }

        let service = DeterministicHashEmbeddingService()
        let written = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: [day],
            modelContainer: container,
            calendar: calendar,
            embeddingService: service
        ) { _ in }

        #expect(written == 1)
        let vectorCount = try await MainActor.run {
            let context = ModelContext(container)
            return try SwiftDataVectorStore(context: context).count()
        }
        #expect(vectorCount == 1)
    }

    @Test func workoutOnlyDayEmbedsVector() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Self.utcDay(2024, 8, 2)
        let workout = AppleWorkout(
            stableID: "embed-run",
            activityType: "Running",
            startDate: day.addingTimeInterval(3600),
            endDate: day.addingTimeInterval(5400),
            durationSec: 1800,
            distanceKm: 5,
            source: AppleWorkoutStore.exportSource
        )
        try await MainActor.run {
            let context = ModelContext(container)
            try AppleWorkoutStore.upsertBatch([workout], in: context)
        }

        let service = DeterministicHashEmbeddingService()
        let written = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: [day],
            modelContainer: container,
            calendar: calendar,
            embeddingService: service
        ) { _ in }

        #expect(written == 1)
    }

    @Test func minimalXMLImport() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
        <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" unit="kcal" startDate="2024-06-15 10:00:00 +0000" value="100" sourceName="Watch"/>
        <Record type="HKCategoryTypeIdentifierSleepAnalysis" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2024-06-14 23:00:00 +0000" endDate="2024-06-15 07:00:00 +0000" sourceName="Watch"/>
        </HealthData>
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "health-fixture-\(UUID().uuidString).xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let state = DailyMetricAggregationState(calendar: Self.utcCalendar)
        let nutrition = DailyNutritionAggregationState(calendar: Self.utcCalendar)
        let delegate = try AppleHealthXMLParser.parse(
            fileURL: url,
            aggregation: state,
            nutritionAggregation: nutrition
        ) { false }
        #expect(delegate.recordsScanned == 2)
        #expect(delegate.tier1RecordsKept == 2)
        #expect(state.dayCount >= 1)
    }

    private static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return utcCalendar.date(from: components)!
    }
}

private enum VectorStoreTestsHelper {
    static func unitVector(axis: Int) -> [Float] {
        var values = [Float](repeating: 0, count: HealthVectorDimension.embeddingGemma)
        values[axis] = 1
        return values
    }
}

private struct DeterministicHashEmbeddingService: EmbeddingService {
    let outputDimension = HealthVectorDimension.embeddingGemma

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: outputDimension)
        let hash = abs(text.hashValue)
        vector[hash % outputDimension] = 1
        return vector
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        try await texts.asyncMap { try await embed($0, kind: kind) }
    }
}

private extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values: [T] = []
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}
