import Foundation
import SwiftData

#if os(iOS)
import os

@MainActor
final class WatchRecoveryPushCoordinator {
    static let shared = WatchRecoveryPushCoordinator()

    private var observer: (any NSObjectProtocol)?

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .healthKitProcessDeltaDidFinish,
            object: nil,
            queue: .main
        ) { notification in
            guard let container = notification.userInfo?["modelContainer"] as? ModelContainer else {
                return
            }
            Task { @MainActor in
                Self.shared.pushLatestRecovery(modelContainer: container)
            }
        }
    }

    func pushLatestRecovery(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let bundle = RecoveryEngine.todayReadinessBundle(in: context)
        WatchConnectivityService.shared.push(
            score: bundle.score,
            personalReadiness: bundle.profile
        )
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp,
            category: "watch"
        ).info(
            "recovery push after sync score=\(Int(bundle.score.value.rounded()), privacy: .public)"
        )
    }

}
#endif
