import Foundation
import SwiftData

#if os(iOS)
import os

@MainActor
final class WatchRecoveryPushCoordinator {
    static let shared = WatchRecoveryPushCoordinator()

    private init() {}

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
