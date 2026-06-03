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
    private var backgroundCoordinator: HealthKitBackgroundCoordinator?
    private(set) var isWorkoutWriteInFlight = false

    init(modelContainer: ModelContainer, calendar: Calendar? = nil) {
        self.modelContainer = modelContainer
        if let calendar {
            self.calendar = calendar
        } else {
            var defaultCalendar = Calendar(identifier: .gregorian)
            defaultCalendar.timeZone = .current
            self.calendar = defaultCalendar
        }
        let coordinator = HealthKitBackgroundCoordinator(healthStore: healthStore) { [weak self] in
            self?.syncDeferredIfDirty()
        }
        backgroundCoordinator = coordinator
        refreshAccessState()
    }

    func refreshAccessState() {
        Task {
            await refreshAccessStateAsync()
        }
    }

    func refreshAccessStateAsync() async {
        accessState = await HealthKitAuthorization.resolveAccessState(healthStore: healthStore)
    }

    func activateBackgroundObserversIfNeeded() {
        guard accessState == .ready else { return }
        backgroundCoordinator?.startIfNeeded()
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            accessState = .unavailable
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: HealthKitTier1Kind.authorizationReadTypes
            )
            Log.healthkit.info("HealthKit read authorization requested for Tier 1 types")
            HealthKitAuthorization.markReadAccessPrompted()
            accessState = .ready
            activateBackgroundObserversIfNeeded()
        } catch {
            Log.healthkit.error(
                "HealthKit authorization request failed: \(String(describing: error), privacy: .public)"
            )
            lastSyncErrorMessage = error.localizedDescription
            if HealthKitAuthorization.isAuthorizationDeniedError(error) {
                accessState = .denied
            } else {
                await refreshAccessStateAsync()
            }
        }
    }

    func syncNow() {
        guard !isSyncing, !isWorkoutWriteInFlight else { return }
        syncTask?.cancel()
        syncTask = Task {
            await performSync(trigger: "manual", clearDirtyOnSuccess: true)
        }
    }

    func syncOnForegroundIfReady() {
        guard accessState == .ready else { return }
        guard !isWorkoutWriteInFlight else { return }
        syncDeferredIfDirty()
    }

    func requestWorkoutWriteAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(
                toShare: HealthKitWorkoutWriter.shareTypes,
                read: HealthKitTier1Kind.authorizationReadTypes
            )
            HealthKitAuthorization.markReadAccessPrompted()
            Log.healthkit.info("workout write authorization requested with read and share types")
            await refreshAccessStateAsync()
            accessState = .ready
        } catch {
            Log.healthkit.error(
                "workout write authorization failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func writeFinishedWorkout(
        sessionID: PersistentIdentifier,
        effortScore: Double?,
        modelContext: ModelContext
    ) async -> HealthKitWorkoutWriteOutcome {
        guard !isWorkoutWriteInFlight else {
            return .failed(message: "Saved in Signal. Health sync is busy. Open Train to retry.")
        }
        isWorkoutWriteInFlight = true
        defer { isWorkoutWriteInFlight = false }

        await requestWorkoutWriteAuthorization()
        return await HealthKitWorkoutWriter.sync(
            sessionID: sessionID,
            effortScore: effortScore,
            modelContext: modelContext,
            healthStore: healthStore
        )
    }

    func syncDeferredIfDirty() {
        guard accessState == .ready else { return }
        guard HealthKitDirtyFlagStore.isDirty else { return }
        guard !isSyncing, !isWorkoutWriteInFlight else { return }
        syncTask?.cancel()
        syncTask = Task {
            await performSync(trigger: "deferred", clearDirtyOnSuccess: true)
        }
    }

    func fetchProfileHealthSnapshot(modelContext: ModelContext) async -> ProfileHealthSnapshot {
        await ProfileHealthKitReader.fetchSnapshot(
            healthStore: healthStore,
            accessState: accessState,
            modelContext: modelContext
        )
    }

    private func performSync(trigger: String, clearDirtyOnSuccess: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            accessState = .unavailable
            return
        }

        await refreshAccessStateAsync()
        if accessState == .notDetermined {
            guard trigger == "manual" else {
                Log.sync.info("sync skipped trigger=\(trigger, privacy: .public); HealthKit authorization not granted")
                return
            }
            await requestAuthorization()
        }
        guard accessState == .ready else { return }
        guard !isWorkoutWriteInFlight else { return }

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
            HealthKitAuthorization.markReadAccessPrompted()
            accessState = .ready
            if clearDirtyOnSuccess {
                backgroundCoordinator?.clearDirtyFlagAfterSuccessfulSync()
            }
            NotificationCenter.default.post(
                name: .healthKitProcessDeltaDidFinish,
                object: nil
            )
            await DerivedMetricsService.shared.invalidateCache()
            Log.sync.info(
                "sync finished trigger=\(trigger, privacy: .public) noOp=\(outcome.noOp, privacy: .public) elapsedSec=\(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)"
            )
        } catch {
            lastSyncErrorMessage = error.localizedDescription
            if HealthKitAuthorization.isAuthorizationDeniedError(error) {
                accessState = .denied
            } else if HealthKitAuthorization.isAuthorizationNotDeterminedError(error) {
                accessState = .notDetermined
            }
            Log.sync.error(
                "sync failed trigger=\(trigger, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }
}
