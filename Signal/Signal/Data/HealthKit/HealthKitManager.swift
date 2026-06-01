import Foundation
import HealthKit
import SwiftData
import Observation
import os

enum HealthKitAccessState: Equatable, Sendable {
    case unavailable
    case notDetermined
    case ready
    case denied
}

@MainActor
@Observable
final class HealthKitManager {
    var accessState: HealthKitAccessState = .notDetermined
    var isSyncing = false
    var lastSyncOutcome: HealthKitSyncOutcome?
    var lastSyncErrorMessage: String?
    var lastSyncFinishedAt: Date?

    private let healthStore = HKHealthStore()
    private let modelContainer: ModelContainer
    private let calendar: Calendar
    private var syncTask: Task<Void, Never>?

    init(modelContainer: ModelContainer, calendar: Calendar? = nil) {
        self.modelContainer = modelContainer
        if let calendar {
            self.calendar = calendar
        } else {
            var defaultCalendar = Calendar(identifier: .gregorian)
            defaultCalendar.timeZone = .current
            self.calendar = defaultCalendar
        }
        refreshAccessState()
    }

    func refreshAccessState() {
        guard HKHealthStore.isHealthDataAvailable() else {
            accessState = .unavailable
            Log.healthkit.warning("Health data unavailable on this device")
            return
        }

        var sawNotDetermined = false
        var sawAuthorized = false
        for kind in HealthKitTier1Kind.allCases {
            let status = healthStore.authorizationStatus(for: kind.sampleType)
            switch status {
            case .notDetermined:
                sawNotDetermined = true
            case .sharingAuthorized:
                sawAuthorized = true
            case .sharingDenied:
                break
            @unknown default:
                break
            }
        }

        if sawNotDetermined {
            accessState = .notDetermined
        } else if sawAuthorized {
            accessState = .ready
        } else {
            accessState = .denied
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            accessState = .unavailable
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: HealthKitTier1Kind.readObjectTypes
            )
            Log.healthkit.info("HealthKit read authorization requested for Tier 1 types")
        } catch {
            Log.healthkit.error(
                "HealthKit authorization request failed: \(String(describing: error), privacy: .public)"
            )
            lastSyncErrorMessage = error.localizedDescription
        }
        refreshAccessState()
    }

    func syncNow() {
        guard !isSyncing else { return }
        syncTask?.cancel()
        syncTask = Task {
            await performForegroundSync(trigger: "manual")
        }
    }

    func syncOnForegroundIfReady() {
        guard accessState != .unavailable, !isSyncing else { return }
        syncTask?.cancel()
        syncTask = Task {
            await performForegroundSync(trigger: "foreground")
        }
    }

    private func performForegroundSync(trigger: String) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            accessState = .unavailable
            return
        }

        refreshAccessState()
        if accessState == .notDetermined {
            await requestAuthorization()
        }

        isSyncing = true
        lastSyncErrorMessage = nil
        let started = Date()
        Log.sync.info("sync started trigger=\(trigger, privacy: .public)")

        defer {
            isSyncing = false
            lastSyncFinishedAt = Date()
            syncTask = nil
        }

        do {
            let embeddingService = EmbeddingBackend.makeService()
            let outcome = try await HealthKitSyncEngine.processDelta(
                healthStore: healthStore,
                modelContainer: modelContainer,
                calendar: calendar,
                embeddingService: embeddingService
            )
            lastSyncOutcome = outcome
            refreshAccessState()
            Log.sync.info(
                "sync finished trigger=\(trigger, privacy: .public) noOp=\(outcome.noOp, privacy: .public) elapsedSec=\(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)"
            )
        } catch {
            lastSyncErrorMessage = error.localizedDescription
            Log.sync.error(
                "sync failed trigger=\(trigger, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private static let deniedMessage =
        "Health access is off. Open Settings > Health > Data Access & Devices > Signal and allow the Tier 1 metrics."
}
