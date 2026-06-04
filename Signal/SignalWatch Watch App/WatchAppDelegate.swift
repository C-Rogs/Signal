import Foundation
import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchLiveWorkoutSessionManager.shared.handleRemoteStart(
                configuration: workoutConfiguration,
                sessionKey: nil
            )
        }
    }
}
