import Foundation
import HealthKit
import Observation
import os
import SwiftData

@MainActor
@Observable
final class LiveWorkoutPhoneSessionManager: NSObject {
    static let shared = LiveWorkoutPhoneSessionManager()

    private(set) var isWorkoutActive = false
    private(set) var statusMessage: String?

    private let healthStore = HKHealthStore()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
        category: "workout"
    )

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionKey: String?
    private var lastUIUpdateAt: Date?
    private var onHeartRateUpdate: ((Int, Date) -> Void)?
    private var stopInFlight: Task<Void, Never>?
    private var isPerformingStop = false

    private override init() {
        super.init()
    }

    func start(
        for workoutSession: WorkoutSession,
        sessionKey: String,
        heartRateHandler: @escaping (Int, Date) -> Void
    ) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "Health access needed for live HR"
            logger.info("phone workout session skipped HealthKit unavailable")
            TrainWorkoutDiagnostics.record("hkPhoneStart skipped unavailable")
            return
        }
        if session != nil {
            logger.info("phone workout session already running")
            return
        }

        let accessState = await HealthKitAuthorization.resolveAccessState(healthStore: healthStore)
        TrainWorkoutDiagnostics.record("hkPhoneStart access=\(Self.accessLogLabel(accessState))")
        guard accessState == .ready else {
            statusMessage = "Health access needed for live HR"
            logger.info("phone workout session skipped access=\(Self.accessLogLabel(accessState), privacy: .public)")
            return
        }

        self.sessionKey = sessionKey
        onHeartRateUpdate = heartRateHandler
        statusMessage = nil

        do {
            let configuration = TrainWorkoutHealthKitConfiguration.make(for: workoutSession)
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession.delegate = self
            workoutBuilder.delegate = self

            session = workoutSession
            builder = workoutBuilder

            let startDate = Date()
            workoutSession.startActivity(with: startDate)
            try await workoutBuilder.beginCollection(at: startDate)

            isWorkoutActive = true
            lastUIUpdateAt = nil
            statusMessage = nil
            logger.info(
                "phone workout session started activity=\(configuration.activityType.rawValue, privacy: .public) sessionKey=\(sessionKey, privacy: .public)"
            )
        } catch {
            isWorkoutActive = false
            if HealthKitAuthorization.isAuthorizationNotDeterminedError(error)
                || HealthKitAuthorization.isAuthorizationDeniedError(error)
            {
                statusMessage = "Health access needed for live HR"
            } else {
                statusMessage = "Live HR unavailable"
            }
            logger.error("phone workout session start failed: \(String(describing: error), privacy: .public)")
            TrainWorkoutDiagnostics.record("hkPhoneStart failed error=\(error.localizedDescription)")
            session = nil
            builder = nil
            self.sessionKey = nil
            onHeartRateUpdate = nil
        }
    }

    func stop(discardHealthKitWorkout: Bool) async {
        switch LiveWorkoutPhoneStopGate.decide(
            hasStopInFlight: stopInFlight != nil,
            hasSession: session != nil && builder != nil
        ) {
        case .awaitInFlight:
            await stopInFlight?.value
            return
        case .noop:
            clearWorkoutState()
            return
        case .performStop:
            break
        }

        let task = Task { @MainActor in
            await performStop(discardHealthKitWorkout: discardHealthKitWorkout)
        }
        stopInFlight = task
        await task.value
        stopInFlight = nil
    }

    private func performStop(discardHealthKitWorkout: Bool) async {
        guard let workoutSession = session, let workoutBuilder = builder else {
            clearWorkoutState()
            return
        }

        isPerformingStop = true
        defer { isPerformingStop = false }

        TrainWorkoutDiagnostics.record("hkPhoneStop begin discard=\(discardHealthKitWorkout)")

        let endDate = Date()
        workoutSession.stopActivity(with: endDate)

        do {
            try await workoutBuilder.endCollection(at: endDate)
            if discardHealthKitWorkout {
                workoutBuilder.discardWorkout()
            } else {
                _ = try await workoutBuilder.finishWorkout()
            }
            workoutSession.end()
            TrainWorkoutDiagnostics.record("hkPhoneStop end ok discard=\(discardHealthKitWorkout)")
            logger.info("phone workout session ended discard=\(discardHealthKitWorkout, privacy: .public)")
        } catch {
            logger.error("phone workout session end failed: \(String(describing: error), privacy: .public)")
            TrainWorkoutDiagnostics.record("hkPhoneStop end error=\(error.localizedDescription)")
            workoutSession.end()
        }

        clearWorkoutState()
    }

    private func clearWorkoutState() {
        session = nil
        builder = nil
        sessionKey = nil
        lastUIUpdateAt = nil
        onHeartRateUpdate = nil
        isWorkoutActive = false
        statusMessage = nil
    }

    private func processHeartRate(from workoutBuilder: HKLiveWorkoutBuilder) {
        let heartRateType = HKQuantityType(.heartRate)
        guard let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        guard bpm > 0 else { return }

        let now = Date()
        guard LiveWorkoutTelemetryThrottle.shouldSend(now: now, lastSent: lastUIUpdateAt) else { return }
        lastUIUpdateAt = now
        onHeartRateUpdate?(bpm, now)
        logger.debug("live HR bpm=\(bpm, privacy: .public) source=phone")
    }

    private static func accessLogLabel(_ state: HealthKitAccessState) -> String {
        switch state {
        case .unavailable: "unavailable"
        case .notDetermined: "notDetermined"
        case .ready: "ready"
        case .denied: "denied"
        }
    }
}

extension LiveWorkoutPhoneSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            logger.info(
                "phone workout session state=\(toState.rawValue, privacy: .public) from=\(fromState.rawValue, privacy: .public)"
            )
            if toState == .ended, !isPerformingStop {
                clearWorkoutState()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "Health access needed for live HR"
            logger.error("phone workout session failed: \(String(describing: error), privacy: .public)")
            clearWorkoutState()
        }
    }
}

extension LiveWorkoutPhoneSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in
            processHeartRate(from: workoutBuilder)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
