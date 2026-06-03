import Foundation
import Observation
import os
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivityReceiver: NSObject {
    var payload: WatchPayload?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cameronro.Signal.watchkitapp",
        category: "watch"
    )

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on watch")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyCachedContext(session.receivedApplicationContext)
        logger.info("WCSession activation requested on watch")
    }

    private func applyCachedContext(_ applicationContext: [String: Any]) {
        guard !applicationContext.isEmpty else { return }
        do {
            payload = try WatchPayload.decode(from: applicationContext)
            logger.info("watch loaded cached context score=\(self.payload?.scoreInt ?? -1, privacy: .public)")
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
            do {
                payload = try WatchPayload.decode(from: applicationContext)
                logger.info("watch received context score=\(self.payload?.scoreInt ?? -1, privacy: .public)")
            } catch {
                logger.error("watch context decode failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

}
