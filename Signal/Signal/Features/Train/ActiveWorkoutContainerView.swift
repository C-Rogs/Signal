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
    @State private var resolveAttempt = 0
    @State private var resolveTimeoutTask: Task<Void, Never>?

    var body: some View {
        workoutContent
            .background(screenBackground.ignoresSafeArea())
            .onAppear {
                resolveSessionIfNeeded()
                scheduleResolveTimeoutIfNeeded()
            }
            .onDisappear {
                resolveTimeoutTask?.cancel()
            }
            .onChange(of: resolveAttempt) { _, _ in
                resolveSessionIfNeeded()
            }
            .onChange(of: coordinator.workoutSurfaceGeneration) { _, _ in
                resolveSessionIfNeeded()
            }
    }

    @ViewBuilder
    private var workoutContent: some View {
        Group {
            if let session {
                ActiveWorkoutView(session: session)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Workout unavailable", systemImage: "figure.run")
                } description: {
                    Text("This session is no longer in progress.")
                } actions: {
                    Button("Retry") {
                        resolveAttempt += 1
                        resolveSessionIfNeeded()
                    }
                    Button("Back to Train") {
                        coordinator.minimizeWorkout(source: "containerUnavailable")
                    }
                }
            } else {
                ProgressView("Loading workout…")
                    .tint(Color("Primary"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private func resolveSessionIfNeeded() {
        coordinator.configure(modelContext: modelContext)
        coordinator.refresh()

        if session == nil,
           let cached = coordinator.activeSession,
           cached.persistentModelID == sessionID,
           cached.endTime == nil
        {
            session = cached
            loadFailed = false
            resolveTimeoutTask?.cancel()
            TrainWorkoutDiagnostics.record("container resolved from coordinator cache exercises=\(cached.exercises.count)")
            return
        }

        if let resolved = resolveSession() {
            session = resolved
            loadFailed = false
            resolveTimeoutTask?.cancel()
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
        TrainWorkoutDiagnostics.record(
            "container FAILED resolve sessionID=\(sessionID) presented=\(coordinator.presentedWorkoutSessionID != nil)"
        )
        Log.workout.error("active workout container could not resolve session")
    }

    private func resolveSession() -> WorkoutSession? {
        if let model = modelContext.model(for: sessionID) as? WorkoutSession {
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

    private func scheduleResolveTimeoutIfNeeded() {
        resolveTimeoutTask?.cancel()
        resolveTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard session == nil, !loadFailed else { return }
            loadFailed = true
            TrainWorkoutDiagnostics.record(
                "container resolveTimeout sessionID=\(sessionID)"
            )
        }
    }
}
