import Foundation
import os
import SwiftData
import UIKit

actor SetHRAttributionTrigger {
    static let shared = SetHRAttributionTrigger()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
        category: "heartrate"
    )
    private var delayedFinishTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var started = false

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        observationTask = Task { [weak self] in
            await self?.observeBackground()
        }
    }

    func scheduleDelayedAttribution(
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

    private func observeBackground() async {
        let background = NotificationCenter.default.notifications(
            named: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        for await _ in background {
            await cancelDelayedAttribution()
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
