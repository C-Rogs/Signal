import Foundation
import os
import SwiftData
import UIKit

actor SetHRAttributionTrigger {
    static let shared = SetHRAttributionTrigger()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cameronro.signal",
        category: "heartrate"
    )
    private var delayedFinishTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

    private init() {
        observationTask = Task { [weak self] in
            await self?.observe()
        }
    }

    private func observe() async {
        let workoutFinish = NotificationCenter.default.notifications(
            named: Notification.Name("workoutDidFinish"),
            object: nil
        )
        let deltaFinish = NotificationCenter.default.notifications(
            named: Notification.Name("healthKitProcessDeltaDidFinish"),
            object: nil
        )
        let background = NotificationCenter.default.notifications(
            named: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await notification in workoutFinish {
                    guard let sessionID = notification.userInfo?["sessionID"] as? PersistentIdentifier,
                          let container = notification.userInfo?["modelContainer"] as? ModelContainer
                    else { continue }
                    await self.scheduleDelayedAttribution(
                        sessionID: sessionID,
                        modelContainer: container
                    )
                }
            }
            group.addTask {
                for await notification in deltaFinish {
                    guard let container = notification.userInfo?["modelContainer"] as? ModelContainer,
                          let span = notification.userInfo?["newHeartRateSampleSpan"] as? DateInterval
                    else { continue }
                    await SetHRAttributionService.shared.attributeSessions(
                        overlapping: span,
                        modelContainer: container
                    )
                }
            }
            group.addTask {
                for await _ in background {
                    await self.cancelDelayedAttribution()
                }
            }
        }
    }

    private func scheduleDelayedAttribution(
        sessionID: PersistentIdentifier,
        modelContainer: ModelContainer
    ) {
        delayedFinishTask?.cancel()
        delayedFinishTask = Task {
            do {
                try await Task.sleep(for: .seconds(45))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await runAttribution(sessionID: sessionID, modelContainer: modelContainer)
        }
    }

    private func cancelDelayedAttribution() {
        delayedFinishTask?.cancel()
        delayedFinishTask = nil
    }

    private func runAttribution(
        sessionID: PersistentIdentifier,
        modelContainer: ModelContainer
    ) async {
        do {
            try await SetHRAttributionService.shared.attribute(
                sessionID: sessionID,
                modelContainer: modelContainer
            )
        } catch {
            logger.error(
                "delayed HR attribution failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
