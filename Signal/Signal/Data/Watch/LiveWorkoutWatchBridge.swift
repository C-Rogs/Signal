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
    private(set) var isLiveHeartRateRequested = false

    private var lockedHeartRateSource: LiveHeartRateSource?
    private var hasActiveWatchHandshake = false
    private var hasActivePhoneSession = false

    private let healthStore = HKHealthStore()
    private let phoneSessionManager = LiveWorkoutPhoneSessionManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
        category: "workout"
    )

    private init() {}

    func beginWatchWorkout(for session: WorkoutSession, modelContext: ModelContext) async {
        await ensureWatchWorkoutStarted(for: session, modelContext: modelContext, forceFullHandshake: true)
    }

    @discardableResult
    func prepareLiveSession(for session: WorkoutSession, modelContext: ModelContext) -> String? {
        guard session.source == WorkoutSessionSource.live, session.endTime == nil else { return nil }
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.info("live watch workout skipped HealthKit unavailable")
            return nil
        }
        let sessionKey = LiveWorkoutSessionKey.ensure(on: session, in: modelContext)
        activeSessionKey = sessionKey
        isLiveHeartRateRequested = true
        if lockedHeartRateSource == nil {
            lockedHeartRateSource = LiveHeartRateSourcePolicy.currentFromWatchConnectivity()
        }
        logger.info(
            "live sessionKey prepared sessionKey=\(sessionKey, privacy: .public) source=\(self.sourceLogLabel, privacy: .public)"
        )
        return sessionKey
    }

    func ensureWatchWorkoutStarted(
        for session: WorkoutSession,
        modelContext: ModelContext,
        forceFullHandshake: Bool = false
    ) async {
        guard let sessionKey = prepareLiveSession(for: session, modelContext: modelContext) else { return }

        if !forceFullHandshake,
           activeSessionKey == sessionKey,
           hasActiveWatchHandshake || hasActivePhoneSession
        {
            logger.info("live workout streaming already active sessionKey=\(sessionKey, privacy: .public)")
            return
        }

        switch lockedHeartRateSource {
        case .watch:
            await ensureWatchSourceStarted(
                for: session,
                sessionKey: sessionKey,
                forceFullHandshake: forceFullHandshake
            )
        case .phoneHealthKit:
            await ensurePhoneSourceStarted(
                for: session,
                sessionKey: sessionKey,
                forceFullHandshake: forceFullHandshake
            )
        case nil:
            break
        }
    }

    private static var lastOutboundRetryAt: Date?

    func retryPendingOutboundTelemetry() {
        guard lockedHeartRateSource == .watch else { return }
        guard let packet = LiveWorkoutOutboundQueue.pending else { return }
        let now = Date()
        if let last = Self.lastOutboundRetryAt, now.timeIntervalSince(last) < 2 {
            return
        }
        Self.lastOutboundRetryAt = now
        send(packet: packet, isRetry: true)
    }

    func heartRateUIState(now: Date = .now) -> LiveWatchHeartRateUIState {
        let accessStatusMessage: String?
        if lockedHeartRateSource == .phoneHealthKit,
           latestHeartRateBPM == nil,
           let message = phoneSessionManager.statusMessage
        {
            accessStatusMessage = message
        } else {
            accessStatusMessage = nil
        }

        return LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: isLiveHeartRateRequested,
            source: lockedHeartRateSource ?? .watch,
            latestHeartRateBPM: latestHeartRateBPM,
            lastHeartRateAt: lastHeartRateAt,
            accessStatusMessage: accessStatusMessage,
            now: now
        )
    }

    func suspendForAppBackground() async {
        guard hasActivePhoneSession else {
            TrainWorkoutDiagnostics.record("livePhoneSession suspendSkipped noActivePhoneSession source=\(sourceLogLabel)")
            return
        }
        hasActivePhoneSession = false
        await phoneSessionManager.stop(discardHealthKitWorkout: true)
        TrainWorkoutDiagnostics.record("livePhoneSession suspendedForBackground sessionKey=\(activeSessionKey ?? "none")")
    }

    func endWatchWorkout() {
        let source = lockedHeartRateSource
        let sessionKey = activeSessionKey

        switch source {
        case .watch:
            if let sessionKey {
                send(packet: LiveWorkoutTelemetryPacket(kind: .sessionStop, sessionKey: sessionKey))
                logger.info("watch workout stop sent sessionKey=\(sessionKey, privacy: .public)")
            }
        case .phoneHealthKit:
            Task {
                await phoneSessionManager.stop(discardHealthKitWorkout: true)
            }
            if let sessionKey {
                logger.info("phone workout stop requested sessionKey=\(sessionKey, privacy: .public)")
            }
        case nil:
            break
        }

        resetStreamingState()
    }

    func ingest(messageData: Data) {
        do {
            let packet = try LiveWorkoutTelemetryPacket.decode(from: messageData)
            guard packet.kind == .heartRateBatch else { return }
            if activeSessionKey == nil {
                activeSessionKey = packet.sessionKey
                isLiveHeartRateRequested = true
                lockedHeartRateSource = .watch
                logger.info(
                    "live HR adopted sessionKey from watch sessionKey=\(packet.sessionKey, privacy: .public)"
                )
            }
            guard lockedHeartRateSource == .watch || lockedHeartRateSource == nil else { return }
            guard packet.sessionKey == activeSessionKey else {
                logger.info(
                    "live HR ignored stale sessionKey=\(packet.sessionKey, privacy: .public) active=\(self.activeSessionKey ?? "none", privacy: .public)"
                )
                return
            }
            guard let samples = packet.heartRateSamples, !samples.isEmpty else { return }
            guard let bpm = LiveWorkoutTelemetryThrottle.coalescedBPM(from: samples) else { return }
            latestHeartRateBPM = bpm
            lastHeartRateAt = samples.last?.timestamp ?? packet.timestamp
            logger.debug(
                "live HR bpm=\(bpm, privacy: .public) samples=\(samples.count, privacy: .public) source=watch"
            )
        } catch {
            logger.error("live HR decode failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func ensureWatchSourceStarted(
        for session: WorkoutSession,
        sessionKey: String,
        forceFullHandshake: Bool
    ) async {
        if hasActiveWatchHandshake && !forceFullHandshake {
            retryPendingOutboundTelemetry()
            sendSessionStart(sessionKey: sessionKey, session: session, requestWatchApp: false)
            return
        }

        if forceFullHandshake || !hasActiveWatchHandshake {
            latestHeartRateBPM = nil
            lastHeartRateAt = nil
        }

        hasActiveWatchHandshake = true
        await requestWatchAppLaunch(for: session, sessionKey: sessionKey)
        sendSessionStart(sessionKey: sessionKey, session: session, requestWatchApp: true)
    }

    private func ensurePhoneSourceStarted(
        for session: WorkoutSession,
        sessionKey: String,
        forceFullHandshake: Bool
    ) async {
        if hasActivePhoneSession && !forceFullHandshake {
            return
        }

        if forceFullHandshake || !hasActivePhoneSession {
            latestHeartRateBPM = nil
            lastHeartRateAt = nil
        }

        await phoneSessionManager.start(for: session, sessionKey: sessionKey) { [weak self] bpm, sampledAt in
            self?.latestHeartRateBPM = bpm
            self?.lastHeartRateAt = sampledAt
        }
        hasActivePhoneSession = phoneSessionManager.isWorkoutActive
    }

    private var sourceLogLabel: String {
        switch lockedHeartRateSource {
        case .watch: "watch"
        case .phoneHealthKit: "phone"
        case nil: "none"
        }
    }

    private func requestWatchAppLaunch(for session: WorkoutSession, sessionKey: String) async {
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
    }

    private func sendSessionStart(sessionKey: String, session: WorkoutSession, requestWatchApp: Bool) {
        if requestWatchApp {
            logger.info(
                "live sessionStart sending after watch launch sessionKey=\(sessionKey, privacy: .public)"
            )
        } else {
            logger.info(
                "live sessionStart re-sent sessionKey=\(sessionKey, privacy: .public)"
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

    private func send(packet: LiveWorkoutTelemetryPacket, isRetry: Bool = false) {
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default

        guard wcSession.activationState == .activated else {
            LiveWorkoutOutboundQueue.enqueue(packet)
            logger.info(
                "live telemetry queued until WCSession activates kind=\(packet.kind.rawValue, privacy: .public) sessionKey=\(packet.sessionKey, privacy: .public)"
            )
            return
        }
        guard wcSession.isPaired, wcSession.isWatchAppInstalled else {
            LiveWorkoutOutboundQueue.enqueue(packet)
            logger.info(
                "live telemetry queued until watch available kind=\(packet.kind.rawValue, privacy: .public) sessionKey=\(packet.sessionKey, privacy: .public)"
            )
            return
        }

        do {
            let data = try packet.encode()
            if wcSession.isReachable {
                wcSession.sendMessageData(data, replyHandler: nil) { [logger] error in
                    logger.error(
                        "live telemetry send failed kind=\(packet.kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                }
                LiveWorkoutOutboundQueue.clearIfMatching(packet)
                logger.info(
                    "live telemetry sent kind=\(packet.kind.rawValue, privacy: .public) sessionKey=\(packet.sessionKey, privacy: .public) retry=\(isRetry, privacy: .public)"
                )
            } else if packet.kind == .sessionStart || packet.kind == .sessionStop {
                wcSession.transferUserInfo([LiveWorkoutTelemetryUserInfoKey.payloadData: data])
                LiveWorkoutOutboundQueue.clearIfMatching(packet)
                logger.info(
                    "live telemetry queued via userInfo kind=\(packet.kind.rawValue, privacy: .public) sessionKey=\(packet.sessionKey, privacy: .public) retry=\(isRetry, privacy: .public)"
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
        _ = LiveWorkoutOutboundQueue.takePending()
        activeSessionKey = nil
        isLiveHeartRateRequested = false
        lockedHeartRateSource = nil
        hasActiveWatchHandshake = false
        hasActivePhoneSession = false
        latestHeartRateBPM = nil
        lastHeartRateAt = nil
    }
}

enum LiveWorkoutOutboundQueue {
    private(set) static var pending: LiveWorkoutTelemetryPacket?

    static func enqueue(_ packet: LiveWorkoutTelemetryPacket) {
        guard packet.kind == .sessionStart || packet.kind == .sessionStop else { return }
        pending = packet
    }

    static func clearIfMatching(_ packet: LiveWorkoutTelemetryPacket) {
        guard pending == packet else { return }
        pending = nil
    }

    static func takePending() -> LiveWorkoutTelemetryPacket? {
        defer { pending = nil }
        return pending
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
