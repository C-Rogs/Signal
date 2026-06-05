import Foundation
import os
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
        category: "watch"
    )

    private var pendingScore: RecoveryScore?
    private var pendingPersonalReadiness: PersonalReadinessProfile?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        logger.info("WCSession activation requested")
    }

    func push(score: RecoveryScore, personalReadiness: PersonalReadinessProfile? = nil) {
        pendingScore = score
        pendingPersonalReadiness = personalReadiness
        cacheForLocalWidgets(score: score, personalReadiness: personalReadiness)
        retryPendingPush()
    }

    private func cacheForLocalWidgets(score: RecoveryScore, personalReadiness: PersonalReadinessProfile?) {
        let payload = WatchPayload(score: score, personalReadiness: personalReadiness)
        guard let context = try? payload.encodeToApplicationContext() else { return }
        let cached = WatchPayloadCache.write(context: context)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchPayloadCache.iosWidgetKind)
        logger.info(
            "ios widget cache updated score=\(payload.scoreInt, privacy: .public) cached=\(cached, privacy: .public)"
        )
    }

    func retryPendingPush() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        guard session.activationState == .activated else {
            if let score = pendingScore {
                logger.info(
                    "watch push deferred until WCSession activates score=\(Int(score.value.rounded()), privacy: .public)"
                )
            }
            return
        }
        deliverPendingScoreIfNeeded(using: session)
    }

    private func deliverPendingScoreIfNeeded(using session: WCSession) {
        guard let score = pendingScore else { return }
        guard session.isPaired else {
            logger.info("watch push skipped not paired")
            return
        }
        if !session.isWatchAppInstalled {
            logger.info("watch push attempting isWatchAppInstalled=false")
        }

        let payload = WatchPayload(score: score, personalReadiness: pendingPersonalReadiness)
        do {
            let context = try payload.encodeToApplicationContext()
            try session.updateApplicationContext(context)
            logger.info(
                "watch context pushed score=\(payload.scoreInt, privacy: .public) classification=\(payload.hrvClassification, privacy: .public)"
            )
            pushComplicationUserInfo(context: context, session: session, score: payload.scoreInt)
        } catch {
            logger.error("watch context push failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func pushComplicationUserInfo(context: [String: Any], session: WCSession, score: Int) {
        guard session.isComplicationEnabled else {
            logger.info("watch complication push skipped complication not enabled")
            return
        }
        _ = session.transferCurrentComplicationUserInfo(context)
        logger.info(
            "watch complication userInfo transferred score=\(score, privacy: .public) remaining=\(session.remainingComplicationUserInfoTransfers, privacy: .public)"
        )
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                logger.error(
                    "WCSession activation failed state=\(activationState.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                return
            }

            logger.info(
                "WCSession activated state=\(activationState.rawValue, privacy: .public) paired=\(session.isPaired, privacy: .public) installed=\(session.isWatchAppInstalled, privacy: .public)"
            )
            if activationState == .activated {
                deliverPendingScoreIfNeeded(using: session)
                LiveWorkoutWatchBridge.shared.retryPendingOutboundTelemetry()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession became inactive")
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession deactivated")
            session.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            logger.info(
                "WCSession watch state changed paired=\(session.isPaired, privacy: .public) installed=\(session.isWatchAppInstalled, privacy: .public)"
            )
            if session.activationState == .activated {
                deliverPendingScoreIfNeeded(using: session)
                LiveWorkoutWatchBridge.shared.retryPendingOutboundTelemetry()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            ingestLiveTelemetryIfNeeded(messageData, transport: "messageData")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            guard let data = userInfo[LiveWorkoutTelemetryUserInfoKey.payloadData] as? Data else { return }
            ingestLiveTelemetryIfNeeded(data, transport: "userInfo")
        }
    }

    private func ingestLiveTelemetryIfNeeded(_ messageData: Data, transport: String) {
        do {
            let packet = try LiveWorkoutTelemetryPacket.decode(from: messageData)
            guard packet.kind == .heartRateBatch else { return }
            logger.info(
                "live HR received via \(transport, privacy: .public) sessionKey=\(packet.sessionKey, privacy: .public)"
            )
        } catch {
            logger.debug("live telemetry userInfo decode skipped: \(String(describing: error), privacy: .public)")
            return
        }
        LiveWorkoutWatchBridge.shared.ingest(messageData: messageData)
    }
}
