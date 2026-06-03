import Foundation
import HealthKit
import os

enum HealthKitStatisticsFetcher {
    static func cumulativeSum(
        quantityType: HKQuantityType,
        dayStart: Date,
        dayEnd: Date,
        unit: HKUnit,
        healthStore: HKHealthStore
    ) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: dayStart,
                end: dayEnd,
                options: .strictStartDate
            )
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    if HealthKitQueryErrors.isNoData(error) {
                        Log.sync.debug(
                            "statistics cumulativeSum no data type=\(quantityType.identifier, privacy: .public)"
                        )
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                guard let quantity = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = quantity.doubleValue(for: unit)
                guard value.isFinite, value > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
