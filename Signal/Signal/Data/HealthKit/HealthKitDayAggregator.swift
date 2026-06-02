import Foundation
import HealthKit

enum HealthKitDayAggregator {
    static func aggregate(
        dayStart: Date,
        healthStore: HKHealthStore,
        calendar: Calendar,
        lookbackStart: Date
    ) async throws -> DailyMetric? {
        let state = DailyMetricAggregationState(calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let source = DailyMetricAggregator.healthKitLiveSource

        for kind in HealthKitTier1Kind.metricKinds {
            if usesStatisticsAggregation(kind) {
                try await ingestStatistics(
                    kind: kind,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    into: state,
                    healthStore: healthStore
                )
                continue
            }

            let predicate: NSPredicate
            switch kind {
            case .sleepAnalysis:
                predicate = HKQuery.predicateForSamples(
                    withStart: lookbackStart,
                    end: dayEnd,
                    options: []
                )
            default:
                predicate = HKQuery.predicateForSamples(
                    withStart: dayStart,
                    end: dayEnd,
                    options: .strictStartDate
                )
            }
            let samples = try await HealthKitSampleFetcher.fetchSamples(
                kind: kind,
                predicate: predicate,
                healthStore: healthStore
            )
            for sample in samples {
                switch kind {
                case .sleepAnalysis:
                    guard calendar.startOfDay(for: sample.endDate) == dayStart else { continue }
                    HealthKitSampleIngestor.ingest(sample, into: state)
                default:
                    guard calendar.startOfDay(for: sample.startDate) == dayStart else { continue }
                    HealthKitSampleIngestor.ingest(sample, into: state)
                }
            }
        }

        let bpPredicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: .strictStartDate
        )
        let bloodPressure = try await HealthKitSampleFetcher.fetchSamples(
            kind: .bloodPressure,
            predicate: bpPredicate,
            healthStore: healthStore
        )
        for sample in bloodPressure {
            guard let correlation = sample as? HKCorrelation else { continue }
            HealthKitSampleIngestor.ingestBloodPressure(correlation, into: state)
        }

        return state.mergedMetric(for: dayStart, source: source)
    }

    private static func usesStatisticsAggregation(_ kind: HealthKitTier1Kind) -> Bool {
        switch kind {
        case .stepCount, .appleExerciseTime, .activeEnergyBurned, .basalEnergyBurned:
            true
        default:
            false
        }
    }

    private static func ingestStatistics(
        kind: HealthKitTier1Kind,
        dayStart: Date,
        dayEnd: Date,
        into state: DailyMetricAggregationState,
        healthStore: HKHealthStore
    ) async throws {
        guard let quantityType = kind.sampleType as? HKQuantityType else { return }

        let unit: HKUnit
        switch kind {
        case .stepCount:
            unit = .count()
        case .appleExerciseTime, .timeInDaylight:
            unit = .minute()
        case .activeEnergyBurned, .basalEnergyBurned:
            unit = .kilocalorie()
        default:
            return
        }

        guard let sum = try await HealthKitStatisticsFetcher.cumulativeSum(
            quantityType: quantityType,
            dayStart: dayStart,
            dayEnd: dayEnd,
            unit: unit,
            healthStore: healthStore
        ) else { return }

        switch kind {
        case .stepCount:
            state.addStepCount(count: sum, startDate: dayStart)
        case .appleExerciseTime:
            state.addAppleExerciseTime(minutes: sum, startDate: dayStart)
        case .activeEnergyBurned:
            state.addActiveEnergy(kcal: sum, startDate: dayStart)
        case .basalEnergyBurned:
            state.addBasalEnergy(kcal: sum, startDate: dayStart)
        default:
            break
        }
    }

    static func aggregateNutrition(
        dayStart: Date,
        healthStore: HKHealthStore,
        calendar: Calendar
    ) async throws -> DailyNutrition? {
        let state = DailyNutritionAggregationState(calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: .strictStartDate
        )

        for kind in HealthKitTier1Kind.nutritionKinds {
            let samples = try await HealthKitSampleFetcher.fetchSamples(
                kind: kind,
                predicate: predicate,
                healthStore: healthStore
            )
            for sample in samples {
                guard calendar.startOfDay(for: sample.startDate) == dayStart else { continue }
                HealthKitSampleIngestor.ingestNutrition(sample, into: state)
            }
        }

        return state.mergedNutrition(for: dayStart, source: DailyMetricAggregator.healthKitLiveSource)
    }
}

enum HealthKitSampleFetcher {
    static func fetchSamples(
        kind: HealthKitTier1Kind,
        predicate: NSPredicate,
        healthStore: HKHealthStore
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: kind.sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
    }
}
