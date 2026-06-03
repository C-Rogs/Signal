import Foundation
import os
import WatchConnectivity

@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cameronro.Signal",
        category: "watch"
    )

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

    func push(score: RecoveryScore) {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.debug("watch push skipped paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
            return
        }

        let payload = WatchPayload(score: score)
        do {
            let context = try payload.encodeToApplicationContext()
            try session.updateApplicationContext(context)
            logger.info(
                "watch context pushed score=\(payload.scoreInt, privacy: .public) classification=\(payload.hrvClassification, privacy: .public)"
            )
        } catch {
            logger.error("watch context push failed: \(String(describing: error), privacy: .public)")
        }
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
            } else {
                logger.info("WCSession activated state=\(activationState.rawValue, privacy: .public)")
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
}
