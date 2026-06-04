import Foundation
import HealthKit
import Observation
import os
import SwiftData
import WatchConnectivity

@MainActor
@Observable
final class LiveWorkoutWatchBridge {
    static let shared = LiveWorkoutWatchBridge()

    private(set) var latestHeartRateBPM: Int?
    private(set) var lastHeartRateAt: Date?
    private(set) var activeSessionKey: String?
    private(set) var isWatchWorkoutRequested = false

    private let healthStore = HKHealthStore()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
        category: "workout"
    )

    private init() {}

    func beginWatchWorkout(for session: WorkoutSession, modelContext: ModelContext) async {
        guard session.source == WorkoutSessionSource.live, session.endTime == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.info("live watch workout skipped HealthKit unavailable")
            return
        }

        let sessionKey = LiveWorkoutSessionKey.ensure(on: session, in: modelContext)
        activeSessionKey = sessionKey
        latestHeartRateBPM = nil
        lastHeartRateAt = nil
        isWatchWorkoutRequested = true

        let configuration = TrainWorkoutHealthKitConfiguration.make(for: session)
        do {
            try await healthStore.startWatchApp(toHandle: configuration)
            logger.info(
                "watch workout app launch requested sessionKey=\(sessionKey, privacy: .public) activity=\(configuration.activityType.rawValue, privacy: .public)"
            )
        } catch {
            logger.error(
                "watch workout app launch failed sessionKey=\(sessionKey, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        let activityRaw = TrainWorkoutHealthKitConfiguration.activityType(for: session).rawValue
        send(
            packet: LiveWorkoutTelemetryPacket(
                kind: .sessionStart,
                sessionKey: sessionKey,
                activityTypeRawValue: activityRaw
            )
        )
    }

    func endWatchWorkout() {
        guard let sessionKey = activeSessionKey else { return }
        send(packet: LiveWorkoutTelemetryPacket(kind: .sessionStop, sessionKey: sessionKey))
        logger.info("watch workout stop sent sessionKey=\(sessionKey, privacy: .public)")
        resetStreamingState()
    }

    func ingest(messageData: Data) {
        do {
            let packet = try LiveWorkoutTelemetryPacket.decode(from: messageData)
            guard packet.kind == .heartRateBatch else { return }
            guard packet.sessionKey == activeSessionKey else {
                logger.debug(
                    "live HR ignored stale sessionKey=\(packet.sessionKey, privacy: .public) active=\(self.activeSessionKey ?? "none", privacy: .public)"
                )
                return
            }
            guard let samples = packet.heartRateSamples, !samples.isEmpty else { return }
            guard let bpm = LiveWorkoutTelemetryThrottle.coalescedBPM(from: samples) else { return }
            latestHeartRateBPM = bpm
            lastHeartRateAt = samples.last?.timestamp ?? packet.timestamp
            logger.debug(
                "live HR bpm=\(bpm, privacy: .public) samples=\(samples.count, privacy: .public)"
            )
        } catch {
            logger.error("live HR decode failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func send(packet: LiveWorkoutTelemetryPacket) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.info("live telemetry deferred until WCSession activates")
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.info("live telemetry skipped watch unavailable")
            return
        }

        do {
            let data = try packet.encode()
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil) { [logger] error in
                    logger.error(
                        "live telemetry send failed kind=\(packet.kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            } else if packet.kind == .sessionStart || packet.kind == .sessionStop {
                session.transferUserInfo([LiveWorkoutTelemetryUserInfoKey.payloadData: data])
                logger.info(
                    "live telemetry queued via userInfo kind=\(packet.kind.rawValue, privacy: .public)"
                )
            } else {
                logger.info(
                    "live telemetry skipped watch not reachable kind=\(packet.kind.rawValue, privacy: .public)"
                )
            }
        } catch {
            logger.error("live telemetry encode failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func resetStreamingState() {
        activeSessionKey = nil
        isWatchWorkoutRequested = false
        latestHeartRateBPM = nil
        lastHeartRateAt = nil
    }
}

enum LiveWorkoutSessionKey {
    @discardableResult
    static func ensure(on session: WorkoutSession, in modelContext: ModelContext) -> String {
        if let existing = session.backupID {
            return existing.uuidString
        }
        let id = UUID()
        session.backupID = id
        try? modelContext.save()
        return id.uuidString
    }
}
