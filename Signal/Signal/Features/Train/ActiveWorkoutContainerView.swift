import SwiftData
import SwiftUI
import os

struct ActiveWorkoutContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    let sessionID: PersistentIdentifier

    @State private var session: WorkoutSession?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let session {
                ActiveWorkoutView(session: session)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Workout unavailable", systemImage: "figure.run")
                } description: {
                    Text("This session is no longer in progress.")
                } actions: {
                    Button("Back to Train") {
                        coordinator.minimizeWorkout()
                    }
                }
            } else {
                ProgressView("Loading workout…")
                    .tint(Color("Primary"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(screenBackground.ignoresSafeArea())
        .onAppear {
            resolveSessionIfNeeded()
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private func resolveSessionIfNeeded() {
        coordinator.configure(modelContext: modelContext)
        coordinator.refresh()

        if let resolved = resolveSession() {
            session = resolved
            loadFailed = false
            TrainWorkoutDiagnostics.record("container resolved exercises=\(resolved.exercises.count)")
            Log.workout.info("active workout container resolved session")
            return
        }

        if session != nil {
            TrainWorkoutDiagnostics.record("container reload missed session; keeping cached view")
            Log.workout.warning("active workout container reload missed session; keeping cached view")
            return
        }

        session = nil
        loadFailed = true
        TrainWorkoutDiagnostics.record("container FAILED resolve sessionID=\(sessionID)")
        Log.workout.error("active workout container could not resolve session")
        coordinator.resetTrainNavigation()
    }

    private func resolveSession() -> WorkoutSession? {
        if let model = try? modelContext.model(for: sessionID) as? WorkoutSession {
            if model.endTime == nil, model.source == WorkoutSessionSource.live {
                return model
            }
        }

        if let active = coordinator.activeSession, active.persistentModelID == sessionID {
            return active
        }

        let liveSource = WorkoutSessionSource.live
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.source == liveSource && session.endTime == nil
            }
        )
        let live = (try? modelContext.fetch(descriptor)) ?? []
        return live.first { $0.persistentModelID == sessionID }
    }
}
