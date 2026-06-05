import Foundation
import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchComplicationRefreshScheduler.scheduleNextRefreshIfNeeded()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    WatchComplicationRefreshScheduler.performScheduledRefresh()
                    refreshTask.setTaskCompletedWithSnapshot(false)
                    WatchComplicationRefreshScheduler.scheduleNextRefreshIfNeeded()
                }
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                Task { @MainActor in
                    WatchComplicationRefreshScheduler.performScheduledRefresh()
                    connectivityTask.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchLiveWorkoutSessionManager.shared.handleRemoteStart(
                configuration: workoutConfiguration,
                sessionKey: nil
            )
        }
    }
}
