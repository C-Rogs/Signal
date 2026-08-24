import Foundation
import SwiftData
import UIKit
import os

enum SystemWorkStep: String, Sendable {
    case invalidateMetrics
    case hrAttribution
    case reflection
    case watchPush
    case workoutMetrics
    case workoutReflection
    case scheduleDelayedHRAttribution
}

actor SystemWorkCoordinator {
    static let shared = SystemWorkCoordinator()

    private var observationTask: Task<Void, Never>?
    private var inFlightTask: Task<Void, Never>?
    private var inFlightWorkID = 0
    private var lastObservedBackgroundGeneration = 0
    private var started = false

    private(set) var testingLastPipelineSteps: [SystemWorkStep] = []
    var testingStepDelay: Duration?

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        observationTask = Task { [weak self] in
            await self?.observe()
        }
    }

    func processHealthKitDeltaForTesting(
        modelContainer: ModelContainer,
        heartRateSpan: DateInterval?
    ) async {
        await enqueueHealthKitDeltaWork(
            modelContainer: modelContainer,
            heartRateSpan: heartRateSpan
        )
    }

    func setTestingStepDelayForTesting(_ delay: Duration?) {
        testingStepDelay = delay
    }

    func testingPipelineSteps() -> [SystemWorkStep] {
        testingLastPipelineSteps
    }

    func cancelInFlightWorkForTesting() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }

    private func observe() async {
        let deltaFinish = NotificationCenter.default.notifications(
            named: .healthKitProcessDeltaDidFinish,
            object: nil
        )
        let workoutFinish = NotificationCenter.default.notifications(
            named: .workoutDidFinish,
            object: nil
        )
        let background = NotificationCenter.default.notifications(
            named: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await notification in deltaFinish {
                    guard let container = notification.userInfo?["modelContainer"] as? ModelContainer else {
                        continue
                    }
                    let span = notification.userInfo?["newHeartRateSampleSpan"] as? DateInterval
                    await self.enqueueHealthKitDeltaWork(
                        modelContainer: container,
                        heartRateSpan: span
                    )
                }
            }
            group.addTask {
                for await notification in workoutFinish {
                    guard let sessionID = notification.userInfo?["sessionID"] as? PersistentIdentifier,
                          let container = notification.userInfo?["modelContainer"] as? ModelContainer
                    else { continue }
                    await self.enqueueWorkoutFinishWork(
                        sessionID: sessionID,
                        modelContainer: container
                    )
                }
            }
            group.addTask {
                for await _ in background {
                    await self.handleDidEnterBackground()
                }
            }
        }
    }

    private func handleDidEnterBackground() async {
        let generation = await MainActor.run {
            AppLifecycleBroker.shared.trueBackgroundGeneration
        }
        guard generation != lastObservedBackgroundGeneration else { return }
        lastObservedBackgroundGeneration = generation
        inFlightTask?.cancel()
        inFlightTask = nil
        Log.sync.info("systemWork cancelled for background gen=\(generation, privacy: .public)")
    }

    private func shouldRunHealthKitDeltaWork() async -> Bool {
        await MainActor.run {
            let broker = AppLifecycleBroker.shared
            guard !broker.resolvedIsInTrueBackground else { return false }
            guard !broker.shouldSkipDeferredSystemWork() else { return false }
            return true
        }
    }

    private func enqueueHealthKitDeltaWork(
        modelContainer: ModelContainer,
        heartRateSpan: DateInterval?
    ) async {
        guard await shouldRunHealthKitDeltaWork() else {
            Log.sync.info("systemWork skip healthKitDelta deferredPolicy")
            return
        }
        inFlightTask?.cancel()
        inFlightWorkID += 1
        let workID = inFlightWorkID
        let task = Task {
            await self.runHealthKitDeltaPipeline(
                modelContainer: modelContainer,
                heartRateSpan: heartRateSpan
            )
        }
        inFlightTask = task
        await task.value
        if workID == inFlightWorkID {
            inFlightTask = nil
        }
    }

    private func enqueueWorkoutFinishWork(
        sessionID: PersistentIdentifier,
        modelContainer: ModelContainer
    ) async {
        inFlightTask?.cancel()
        inFlightWorkID += 1
        let workID = inFlightWorkID
        let task = Task {
            await self.runWorkoutFinishPipeline(
                sessionID: sessionID,
                modelContainer: modelContainer
            )
        }
        inFlightTask = task
        await task.value
        if workID == inFlightWorkID {
            inFlightTask = nil
        }
    }

    private func runHealthKitDeltaPipeline(
        modelContainer: ModelContainer,
        heartRateSpan: DateInterval?
    ) async {
        testingLastPipelineSteps = []
        Log.sync.info("systemWork healthKitDelta begin")

        await recordStep(.invalidateMetrics)
        await DerivedMetricsService.shared.invalidateCache()
        guard await continueUnlessCancelled() else { return }
        guard await applyTestingStepDelay() else { return }

        if let heartRateSpan {
            await recordStep(.hrAttribution)
            await SetHRAttributionService.shared.attributeSessions(
                overlapping: heartRateSpan,
                modelContainer: modelContainer
            )
            guard await continueUnlessCancelled() else { return }
            guard await applyTestingStepDelay() else { return }
        }

        if await ReflectionEngine.shared.mayStartReflection() {
            await recordStep(.reflection)
            _ = await ReflectionEngine.shared.runReflection(in: ModelContext(modelContainer))
            guard await continueUnlessCancelled() else { return }
            guard await applyTestingStepDelay() else { return }
        } else {
            Log.recovery.info("systemWork skip reflection debounced")
        }

        await recordStep(.watchPush)
        await pushWatchRecovery(modelContainer: modelContainer)
        Log.sync.info("systemWork healthKitDelta finished")
    }

    private func runWorkoutFinishPipeline(
        sessionID: PersistentIdentifier,
        modelContainer: ModelContainer
    ) async {
        testingLastPipelineSteps = []
        Log.sync.info("systemWork workoutFinish begin")

        await recordStep(.workoutMetrics)
        await DerivedMetricsService.shared.handleWorkoutDidFinish(
            sessionID: sessionID,
            modelContainer: modelContainer
        )
        guard await continueUnlessCancelled() else { return }
        guard await applyTestingStepDelay() else { return }

        await recordStep(.scheduleDelayedHRAttribution)
        await SetHRAttributionTrigger.shared.scheduleDelayedAttribution(
            sessionID: sessionID,
            modelContainer: modelContainer
        )
        guard await continueUnlessCancelled() else { return }
        guard await applyTestingStepDelay() else { return }

        if await ReflectionEngine.shared.mayStartReflection() {
            await recordStep(.workoutReflection)
            _ = await ReflectionEngine.shared.runReflection(in: ModelContext(modelContainer))
        }
        Log.sync.info("systemWork workoutFinish finished")
    }

    private func pushWatchRecovery(modelContainer: ModelContainer) async {
        await MainActor.run {
            WatchRecoveryPushCoordinator.shared.pushLatestRecovery(modelContainer: modelContainer)
        }
    }

    private func recordStep(_ step: SystemWorkStep) {
        testingLastPipelineSteps.append(step)
    }

    private func applyTestingStepDelay() async -> Bool {
        guard let testingStepDelay else { return true }
        do {
            try await Task.sleep(for: testingStepDelay)
        } catch {
            return false
        }
        return await continueUnlessCancelled()
    }

    private func continueUnlessCancelled() async -> Bool {
        guard !Task.isCancelled else {
            Log.sync.info("systemWork pipeline cancelled")
            return false
        }
        return true
    }
}
