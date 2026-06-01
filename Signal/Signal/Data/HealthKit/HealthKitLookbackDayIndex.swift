import Foundation
import HealthKit

enum HealthKitLookbackDayIndex {
    static func dayStarts(
        healthStore: HKHealthStore,
        calendar: Calendar,
        lookbackStart: Date
    ) async throws -> Set<Date> {
        let predicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: nil,
            options: .strictStartDate
        )
        var days: Set<Date> = []
        for kind in HealthKitTier1Kind.allCases {
            let samples = try await HealthKitSampleFetcher.fetchSamples(
                kind: kind,
                predicate: predicate,
                healthStore: healthStore
            )
            for sample in samples {
                days.insert(HealthKitSampleIngestor.affectedWakeDay(for: sample, calendar: calendar))
            }
        }
        return days
    }
}
