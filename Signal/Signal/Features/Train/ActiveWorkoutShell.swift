import SwiftData
import SwiftUI

struct ActiveWorkoutShell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator

    let sessionID: PersistentIdentifier

    var body: some View {
        NavigationStack {
            ActiveWorkoutContainerView(sessionID: sessionID)
        }
        .id(coordinator.workoutSurfaceGeneration)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TrainChrome.screenBackground(colorScheme: colorScheme).ignoresSafeArea())
    }
}
