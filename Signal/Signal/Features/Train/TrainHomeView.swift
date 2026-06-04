import SwiftData
import SwiftUI

struct TrainHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(LiveWorkoutWatchBridge.self) private var watchBridge

    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endTime != nil },
        sort: \WorkoutSession.startTime,
        order: .reverse
    )
    private var completedSessions: [WorkoutSession]

    @Query private var liveSessions: [WorkoutSession]

    @State private var path: [TrainRoute] = []
    @State private var editingRoutine: Routine?
    @State private var showNewRoutine = false
    @State private var errorMessage: String?
    @State private var healthKitWriteNote: String?

    init() {
        let liveSource = WorkoutSessionSource.live
        _liveSessions = Query(
            filter: #Predicate<WorkoutSession> { session in
                session.source == liveSource && session.endTime == nil
            },
            sort: \WorkoutSession.startTime,
            order: .reverse
        )
    }

    private var store: LiveWorkoutStore {
        LiveWorkoutStore(context: modelContext)
    }

    private var recentSessions: [WorkoutSession] {
        Array(completedSessions.prefix(10))
    }

    private var inProgressSession: WorkoutSession? {
        liveSessions.first ?? coordinator.activeSession
    }

    var body: some View {
        NavigationStack(path: $path) {
            trainList
                .navigationDestination(for: TrainRoute.self) { route in
                    routeDestination(route)
                }
        }
        .onAppear {
            coordinator.configure(modelContext: modelContext)
            collapseWorkoutNavigationIfNeeded()
            consumePendingRouteIfNeeded()
            consumeHealthKitWriteNoteIfNeeded()
        }
        .onChange(of: coordinator.pendingHealthKitWriteNote) { _, _ in
            consumeHealthKitWriteNoteIfNeeded()
        }
        .onChange(of: coordinator.pendingTrainRoute) { _, route in
            guard route != nil else { return }
            consumePendingRouteIfNeeded()
        }
        .onChange(of: coordinator.trainNavigationResetToken) { _, _ in
            path.removeAll()
        }
        .onChange(of: liveSessions) { _, sessions in
            coordinator.refresh()
            if sessions.isEmpty, coordinator.pendingWellnessSessionID == nil {
                path.removeAll()
            }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty {
                coordinator.refresh()
            }
        }
        .sheet(isPresented: $showNewRoutine) {
            RoutineEditorView(routine: nil)
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorView(routine: routine)
        }
    }

    @ViewBuilder
    private var trainList: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if let healthKitWriteNote {
                    Section {
                        Text(healthKitWriteNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        startOrResumeWorkout()
                    } label: {
                        Label(
                            inProgressSession == nil ? "Start Workout" : "Continue workout",
                            systemImage: inProgressSession == nil ? "play.fill" : "arrow.forward.circle.fill"
                        )
                        .font(.headline)
                    }
                    .accessibilityIdentifier("startWorkoutButton")
                }

                Section("Routines") {
                    if routines.isEmpty {
                        ContentUnavailableView {
                            Label("No routines", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("Create a routine or start an empty workout.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(routines, id: \.persistentModelID) { routine in
                            Button {
                                startRoutine(routine)
                            } label: {
                                HStack {
                                    Text(routine.name)
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(Color("Primary"))
                                }
                            }
                            .contextMenu {
                                Button("Edit") {
                                    editingRoutine = routine
                                }
                                Button("Delete", role: .destructive) {
                                    deleteRoutine(routine)
                                }
                            }
                        }
                    }
                }

                Section("Recent") {
                    if recentSessions.isEmpty {
                        Text("No completed workouts yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentSessions, id: \.persistentModelID) { session in
                            NavigationLink(value: TrainRoute.history(session.persistentModelID)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                    if let end = session.endTime {
                                        Text(end.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewRoutine = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("newRoutineButton")
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: TrainRoute) -> some View {
        switch route {
        case .activeWorkout(let sessionID):
            ActiveWorkoutContainerView(sessionID: sessionID)
        case .history(let id):
            if let session = completedSessions.first(where: { $0.persistentModelID == id }) {
                WorkoutHistoryDetailView(session: session)
            } else {
                ContentUnavailableView("Session not found", systemImage: "questionmark")
            }
        case .editRoutine:
            ContentUnavailableView("Routine editor unavailable", systemImage: "list.bullet")
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private func collapseWorkoutNavigationIfNeeded() {
        guard coordinator.consumeCollapseWorkoutNavigationFlag() else { return }
        path.removeAll()
    }

    private func consumePendingRouteIfNeeded() {
        guard case .activeWorkout(let sessionID) = coordinator.pendingTrainRoute else { return }
        openActiveWorkout(sessionID: sessionID)
        coordinator.pendingTrainRoute = nil
    }

    private func consumeHealthKitWriteNoteIfNeeded() {
        guard let note = coordinator.consumeHealthKitWriteNote() else { return }
        healthKitWriteNote = note
    }

    private func openActiveWorkout(sessionID: PersistentIdentifier? = nil) {
        coordinator.refresh()
        guard let session = inProgressSession else { return }
        let targetID = sessionID ?? session.persistentModelID
        let route = TrainRoute.activeWorkout(targetID)
        if !path.contains(route) {
            path.append(route)
        }
    }

    private func startOrResumeWorkout() {
        do {
            if let session = inProgressSession {
                Task {
                    await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
                }
                openActiveWorkout(sessionID: session.persistentModelID)
            } else {
                let session = try store.startEmpty()
                coordinator.refresh()
                Task {
                    await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
                }
                path.append(.activeWorkout(session.persistentModelID))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRoutine(_ routine: Routine) {
        do {
            if let session = inProgressSession {
                Task {
                    await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
                }
                openActiveWorkout(sessionID: session.persistentModelID)
                return
            }
            let session = try store.start(from: routine)
            coordinator.refresh()
            Task {
                await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
            }
            path.append(.activeWorkout(session.persistentModelID))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        try? modelContext.save()
    }
}
