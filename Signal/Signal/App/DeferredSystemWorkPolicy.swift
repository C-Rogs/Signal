import Foundation

enum DeferredSystemWorkPolicy {
    private static let trainCooldownSeconds: TimeInterval = 60
    private static let foregroundStabilitySeconds: TimeInterval = 3

    @MainActor private static var trainSensitiveUntil: Date?

    @MainActor
    static func noteTrainInteractionEnded() {
        trainSensitiveUntil = Date().addingTimeInterval(trainCooldownSeconds)
        TrainWorkoutDiagnostics.record(
            "trainInteractionCooldown began seconds=\(Int(trainCooldownSeconds))"
        )
    }

    @MainActor
    static var isTrainInteractionCooldownActive: Bool {
        guard let trainSensitiveUntil else { return false }
        return Date() < trainSensitiveUntil
    }

    @MainActor
    static func mayStartDeferredHealthKitSync(
        broker: AppLifecycleBroker = .shared
    ) -> Bool {
        guard !broker.shouldSkipDeferredSystemWork() else { return false }
        guard !broker.resolvedIsInTrueBackground else { return false }
        guard !isTrainInteractionCooldownActive else { return false }
        guard broker.isForegroundStableForDeferredWork(
            minimumSeconds: foregroundStabilitySeconds
        ) else { return false }
        return true
    }
}
