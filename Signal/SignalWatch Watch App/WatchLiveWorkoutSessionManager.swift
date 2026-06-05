import Foundation
import HealthKit
import Observation
import os
import WatchConnectivity

@MainActor
@Observable
final class WatchLiveWorkoutSessionManager: NSObject {
    static let shared = WatchLiveWorkoutSessionManager()

    private(set) var isWorkoutActive = false
    private(set) var latestHeartRateBPM: Int?
    private(set) var statusMessage: String?

    private let healthStore = HKHealthStore()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.watchApp,
        category: "watch"
    )

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionKey: String?
    private var lastSentAt: Date?
    private var pendingSamples: [LiveWorkoutHeartRateSample] = []

    private override init() {
        super.init()
    }

    func handleRemoteStart(configuration: HKWorkoutConfiguration, sessionKey: String?) async {
        if let sessionKey {
            self.sessionKey = sessionKey
        }
        let wasActive = session != nil
        await start(configuration: configuration)
        if wasActive, self.sessionKey != nil {
            flushPendingHeartRate(force: true)
        }
    }

    func handleCommand(_ packet: LiveWorkoutTelemetryPacket) async {
        switch packet.kind {
        case .sessionStart:
            sessionKey = packet.sessionKey
            logger.info("watch workout sessionKey bound sessionKey=\(packet.sessionKey, privacy: .public)")
            if session == nil {
                let configuration = TrainWorkoutHealthKitConfiguration.make(
                    activityTypeRawValue: packet.activityTypeRawValue
                )
                await start(configuration: configuration)
                flushPendingHeartRate(force: true)
            } else {
                flushPendingHeartRate(force: true)
            }
        case .sessionStop:
            guard packet.sessionKey == sessionKey else { return }
            await stop(discardHealthKitWorkout: true)
        case .heartRateBatch:
            break
        }
    }

    private func start(configuration: HKWorkoutConfiguration) async {
        guard WatchHealthKitAuthorization.isConfiguredForHealthKit else {
            statusMessage = "Health access not set up on watch"
            logger.error("watch workout session skipped missing HealthKit Info.plist keys or capability")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "Health data unavailable"
            logger.info("watch workout session skipped HealthKit unavailable")
            return
        }
        if session != nil {
            logger.info("watch workout session already running")
            return
        }

        statusMessage = "Starting workout..."
        _ = await WatchHealthKitAuthorization.requestWorkoutAccessIfNeeded()

        do {
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
            latestHeartRateBPM = nil
            statusMessage = nil
            lastSentAt = nil
            pendingSamples = []
            logger.info(
                "watch workout session started activity=\(configuration.activityType.rawValue, privacy: .public) sessionKey=\(self.sessionKey ?? "pending", privacy: .public)"
            )
        } catch {
            isWorkoutActive = false
            statusMessage = "Workout could not start"
            logger.error("watch workout session start failed: \(String(describing: error), privacy: .public)")
            session = nil
            builder = nil
        }
    }

    func stop(discardHealthKitWorkout: Bool) async {
        guard let workoutSession = session, let workoutBuilder = builder else {
            clearWorkoutState()
            return
        }

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
            flushPendingHeartRate(force: true)
            logger.info("watch workout session ended discard=\(discardHealthKitWorkout, privacy: .public)")
        } catch {
            logger.error("watch workout session end failed: \(String(describing: error), privacy: .public)")
            workoutSession.end()
        }

        clearWorkoutState()
    }

    private func clearWorkoutState() {
        session = nil
        builder = nil
        sessionKey = nil
        lastSentAt = nil
        pendingSamples = []
        isWorkoutActive = false
        latestHeartRateBPM = nil
        statusMessage = nil
    }

    private func processHeartRate(from workoutBuilder: HKLiveWorkoutBuilder) {
        let heartRateType = HKQuantityType(.heartRate)
        guard let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        guard bpm > 0 else { return }

        latestHeartRateBPM = bpm
        let sample = LiveWorkoutHeartRateSample(bpm: bpm, timestamp: Date())
        pendingSamples.append(sample)

        let now = Date()
        guard LiveWorkoutTelemetryThrottle.shouldSend(now: now, lastSent: lastSentAt) else { return }
        flushPendingHeartRate(force: false, now: now)
    }

    private func flushPendingHeartRate(force: Bool, now: Date = Date()) {
        guard let sessionKey else { return }
        let batch = LiveWorkoutTelemetryThrottle.trimmedBatch(pendingSamples)
        guard force || !batch.isEmpty else { return }
        pendingSamples.removeAll(keepingCapacity: true)

        let packet = LiveWorkoutTelemetryPacket(
            kind: .heartRateBatch,
            sessionKey: sessionKey,
            timestamp: now,
            heartRateSamples: batch
        )
        send(packet: packet)
        lastSentAt = now
        logger.info(
            "live HR batch sent sessionKey=\(sessionKey, privacy: .public) samples=\(batch.count, privacy: .public)"
        )
    }

    private func send(packet: LiveWorkoutTelemetryPacket) {
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        guard wcSession.activationState == .activated else { return }

        do {
            let data = try packet.encode()
            if wcSession.isReachable {
                wcSession.sendMessageData(data, replyHandler: nil) { [logger] error in
                    logger.error(
                        "live HR send failed error=\(error.localizedDescription, privacy: .public)"
                    )
                }
                logger.info("live HR sent via messageData sessionKey=\(packet.sessionKey, privacy: .public)")
            } else if packet.kind == .heartRateBatch {
                wcSession.transferUserInfo([LiveWorkoutTelemetryUserInfoKey.payloadData: data])
                logger.info(
                    "live HR queued via userInfo sessionKey=\(packet.sessionKey, privacy: .public)"
                )
            }
        } catch {
            logger.error("live HR encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension WatchLiveWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            logger.info(
                "watch workout session state=\(toState.rawValue, privacy: .public) from=\(fromState.rawValue, privacy: .public)"
            )
            if toState == .ended {
                clearWorkoutState()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "Workout session failed"
            logger.error("watch workout session failed: \(String(describing: error), privacy: .public)")
            clearWorkoutState()
        }
    }
}

extension WatchLiveWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
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

enum TrainWorkoutHealthKitConfiguration {
    static func make(activityTypeRawValue: UInt?) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityTypeRawValue.flatMap { HKWorkoutActivityType(rawValue: $0) }
            ?? .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }
}
