import Foundation
import HealthKit
import os

enum WatchHealthKitAuthorization {
    private static let didRequestKey = "signal.watch.healthKit.didRequestWorkout"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.watchApp,
        category: "watch"
    )

    static var isConfiguredForHealthKit: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let bundle = Bundle.main
        let share = bundle.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String
        let update = bundle.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") as? String
        return !(share?.isEmpty ?? true) && !(update?.isEmpty ?? true)
    }

    static func requestWorkoutAccessIfNeeded() async -> Bool {
        guard isConfiguredForHealthKit else {
            logger.error(
                "watch HealthKit skipped: add NSHealthShareUsageDescription and NSHealthUpdateUsageDescription to the watch target Info (see WatchApp-Info.plist)"
            )
            return false
        }

        if UserDefaults.standard.bool(forKey: didRequestKey) {
            return true
        }

        let healthStore = HKHealthStore()
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKObjectType.workoutType(),
        ]

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                UserDefaults.standard.set(true, forKey: didRequestKey)
                if let error {
                    logger.error(
                        "watch HealthKit authorization failed: \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    logger.info("watch HealthKit authorization finished success=\(success, privacy: .public)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
