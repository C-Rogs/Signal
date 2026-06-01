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

        for kind in HealthKitTier1Kind.allCases {
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

        return state.mergedMetric(for: dayStart, source: source)
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
