import Foundation
import HealthKit
import UIKit
import os

@MainActor
final class HealthKitBackgroundCoordinator {
    private let healthStore: HKHealthStore
    private var observerQueries: [HKObserverQuery] = []
    private var protectedDataObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var hasStarted = false
    private let onDeferredSync: @MainActor () -> Void

    init(healthStore: HKHealthStore, onDeferredSync: @escaping @MainActor () -> Void) {
        self.healthStore = healthStore
        self.onDeferredSync = onDeferredSync
    }

    func startIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !hasStarted else { return }
        hasStarted = true
        registerObservers()
        enableBackgroundDelivery()
        observeUnlockAndForeground()
        Log.sync.info("HealthKit background observers started after authorization")
    }

    func stop() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        if let protectedDataObserver {
            NotificationCenter.default.removeObserver(protectedDataObserver)
            self.protectedDataObserver = nil
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
    }

    private func registerObservers() {
        for kind in HealthKitTier1Kind.allCases {
            let sampleType = kind.sampleType
            let typeIdentifier = kind.anchorTypeIdentifier
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
                defer { completionHandler() }
                if let error {
                    if HealthKitAuthorization.isAuthorizationNotDeterminedError(error) {
                        Log.sync.debug(
                            "observer skipped type=\(typeIdentifier, privacy: .public); authorization not determined"
                        )
                        return
                    }
                    Log.sync.error(
                        "observer error type=\(typeIdentifier, privacy: .public) error=\(String(describing: error), privacy: .public)"
                    )
                    return
                }
                Log.sync.info("observer fired type=\(typeIdentifier, privacy: .public)")
                HealthKitDirtyFlagStore.setDirty()
                Log.sync.info("dirty flag set type=\(typeIdentifier, privacy: .public)")
            }
            observerQueries.append(query)
            healthStore.execute(query)
            Log.sync.info("observer registered type=\(typeIdentifier, privacy: .public)")
        }
    }

    private func enableBackgroundDelivery() {
        for kind in HealthKitTier1Kind.allCases {
            guard kind.supportsBackgroundDelivery else { continue }
            let sampleType = kind.sampleType
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { success, error in
                if let error {
                    Log.sync.error(
                        "enableBackgroundDelivery failed type=\(kind.anchorTypeIdentifier, privacy: .public) error=\(String(describing: error), privacy: .public)"
                    )
                } else {
                    Log.sync.info(
                        "enableBackgroundDelivery type=\(kind.anchorTypeIdentifier, privacy: .public) success=\(success, privacy: .public)"
                    )
                }
            }
        }
    }

    private func observeUnlockAndForeground() {
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.sync.info("protectedDataDidBecomeAvailable received")
            self?.runDeferredSyncIfNeeded(trigger: "protectedData")
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.runDeferredSyncIfNeeded(trigger: "foreground")
        }
    }

    private func runDeferredSyncIfNeeded(trigger: String) {
        guard HealthKitDirtyFlagStore.isDirty else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            Log.sync.info("deferred sync skipped trigger=\(trigger, privacy: .public); protected data unavailable")
            return
        }
        Log.sync.info("processDelta scheduled trigger=\(trigger, privacy: .public)")
        onDeferredSync()
    }

    func clearDirtyFlagAfterSuccessfulSync() {
        HealthKitDirtyFlagStore.clear()
        Log.sync.info("dirty flag cleared after processDelta")
    }
}
