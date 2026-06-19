import Foundation

enum LiveWorkoutCoordinatorLaunchState {
    private static let wasViewingLiveWorkoutKey = "signal.train.wasViewingLiveWorkout"

    static func markProcessLaunched() {
        collapseNavigationOnNextTrainAppear = true
    }

    static var collapseNavigationOnNextTrainAppear = true

    static var shouldResumeLiveWorkoutAfterRelaunch: Bool {
        UserDefaults.standard.bool(forKey: wasViewingLiveWorkoutKey)
    }

    static func noteLiveWorkoutViewing(_ viewing: Bool) {
        UserDefaults.standard.set(viewing, forKey: wasViewingLiveWorkoutKey)
    }
}
