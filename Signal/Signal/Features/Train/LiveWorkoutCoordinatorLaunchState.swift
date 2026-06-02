import Foundation

enum LiveWorkoutCoordinatorLaunchState {
    private static let launchKey = "signal.workout.lastProcessLaunch"

    static func markProcessLaunched() {
        collapseNavigationOnNextTrainAppear = true
    }

    static var collapseNavigationOnNextTrainAppear = true
}
