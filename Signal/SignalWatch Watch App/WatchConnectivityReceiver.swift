import Foundation
import Observation
import os
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivityReceiver: NSObject {
    var payload: WatchPayload?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.watchApp,
        category: "watch"
    )

    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on watch")
            return
        }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
            session.activate()
            logger.info("WCSession activation requested on watch")
        } else if session.delegate === self, session.activationState != .activated {
            session.activate()
        }
        hydratePayloadFromCaches(session: session)
    }

    private func hydratePayloadFromCaches(session: WCSession) {
        if !session.receivedApplicationContext.isEmpty {
            applyCachedContext(session.receivedApplicationContext)
        }
        if payload == nil, let context = WatchPayloadCache.readContext() {
            applyCachedContext(context)
            logger.info("watch loaded recovery from app group cache")
        }
    }

    private func applyCachedContext(_ applicationContext: [String: Any]) {
        guard !applicationContext.isEmpty else { return }
        do {
            payload = try WatchPayload.decode(from: applicationContext)
            logger.info("watch loaded cached context score=\(self.payload?.scoreInt ?? -1, privacy: .public)")
            WatchComplicationRefresh.publish(context: applicationContext)
            WatchComplicationRefreshScheduler.scheduleNextRefreshIfNeeded()
            logger.info("watch complication timeline reload requested")
        } catch {
            logger.error("watch cached context decode failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
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
            } else {
                logger.info("WCSession activated on watch state=\(activationState.rawValue, privacy: .public)")
                applyCachedContext(session.receivedApplicationContext)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            applyCachedContext(applicationContext)
            logger.info("watch received context score=\(self.payload?.scoreInt ?? -1, privacy: .public)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            guard !userInfo.isEmpty else { return }
            if let data = userInfo[LiveWorkoutTelemetryUserInfoKey.payloadData] as? Data {
                await ingestLiveTelemetry(data)
                return
            }
            applyCachedContext(userInfo)
            logger.info("watch received complication userInfo score=\(self.payload?.scoreInt ?? -1, privacy: .public)")
        }
    }

    private func ingestLiveTelemetry(_ data: Data) async {
        do {
            let packet = try LiveWorkoutTelemetryPacket.decode(from: data)
            await WatchLiveWorkoutSessionManager.shared.handleCommand(packet)
            logger.info("watch received live telemetry userInfo kind=\(packet.kind.rawValue, privacy: .public)")
        } catch {
            logger.error("watch live telemetry userInfo decode failed: \(String(describing: error), privacy: .public)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            do {
                let packet = try LiveWorkoutTelemetryPacket.decode(from: messageData)
                await WatchLiveWorkoutSessionManager.shared.handleCommand(packet)
            } catch {
                logger.error("watch live telemetry decode failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

}
