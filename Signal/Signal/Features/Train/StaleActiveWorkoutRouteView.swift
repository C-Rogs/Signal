import SwiftData
import SwiftUI

struct StaleActiveWorkoutRouteView: View {
    @Environment(LiveWorkoutCoordinator.self) private var coordinator

    let sessionID: PersistentIdentifier

    var body: some View {
        ProgressView("Opening workout…")
            .tint(Color("Primary"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                TrainWorkoutDiagnostics.record(
                    "staleActiveWorkoutRoute redirect session=\(String(describing: sessionID))"
                )
                coordinator.presentWorkout(sessionID: sessionID)
                coordinator.requestStripActiveWorkoutRoute()
            }
    }
}
