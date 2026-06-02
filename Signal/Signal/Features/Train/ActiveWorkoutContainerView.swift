import SwiftData
import SwiftUI
import os

struct ActiveWorkoutContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

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
                        dismiss()
                    }
                }
            } else {
                ProgressView("Loading workout…")
                    .tint(Color("Primary"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(screenBackground.ignoresSafeArea())
        .task(id: sessionID) {
            await loadActiveSession()
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    @MainActor
    private func loadActiveSession() async {
        coordinator.configure(modelContext: modelContext)
        coordinator.refresh()

        if let resolved = resolveSession() {
            session = resolved
            loadFailed = false
            return
        }

        session = nil
        loadFailed = true
        Log.workout.error("active workout container could not resolve session")
        coordinator.resetTrainNavigation()
        dismiss()
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
