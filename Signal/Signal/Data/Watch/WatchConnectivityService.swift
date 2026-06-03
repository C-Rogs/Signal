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

    private var pendingScore: RecoveryScore?

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
        pendingScore = score
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.info("watch push deferred until WCSession activates score=\(Int(score.value.rounded()), privacy: .public)")
            return
        }
        deliverPendingScoreIfNeeded(using: session)
    }

    private func deliverPendingScoreIfNeeded(using session: WCSession) {
        guard let score = pendingScore else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.info(
                "watch push skipped paired=\(session.isPaired, privacy: .public) installed=\(session.isWatchAppInstalled, privacy: .public)"
            )
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
                return
            }

            logger.info(
                "WCSession activated state=\(activationState.rawValue, privacy: .public) paired=\(session.isPaired, privacy: .public) installed=\(session.isWatchAppInstalled, privacy: .public)"
            )
            if activationState == .activated {
                deliverPendingScoreIfNeeded(using: session)
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
