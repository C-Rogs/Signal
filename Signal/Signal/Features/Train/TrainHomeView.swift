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
    @State private var busyDayChipTitle: String?
    @State private var showDeloadBanner = false
    @State private var showImportWorkout = false
    @AppStorage("trainDeloadBannerDismissedWeek") private var dismissedDeloadWeek = ""

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
            reloadBusyDayChip()
            reloadDeloadBanner()
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
            guard sessions.isEmpty else { return }
            guard coordinator.pendingWellnessSessionID == nil else { return }
            guard coordinator.activeSession == nil else { return }
            path.removeAll()
        }
        .onChange(of: path) { _, newPath in
            coordinator.isViewingActiveWorkout = newPath.contains { route in
                if case .activeWorkout = route { return true }
                return false
            }
            TrainWorkoutDiagnostics.record(
                "trainPath count=\(newPath.count) viewingWorkout=\(coordinator.isViewingActiveWorkout) routes=\(newPath.map(\.diagnosticLabel).joined(separator: ","))"
            )
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
        .sheet(isPresented: $showImportWorkout) {
            GeminiWorkoutImportView { sessionID in
                path.append(.activeWorkout(sessionID))
            }
        }
    }

    @ViewBuilder
    private var trainList: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let errorMessage {
                        inlineNotice(errorMessage, color: .red)
                    }

                    if let healthKitWriteNote {
                        inlineNotice(healthKitWriteNote, color: Color("TextSecondary"))
                    }

                    statusBanners

                    primaryActions

                    routinesSection

                    recentSection
                }
                .padding(.horizontal, TrainChrome.horizontalPadding)
                .padding(.vertical, 8)
            }
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
    private var statusBanners: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showDeloadBanner {
                HStack(alignment: .top, spacing: 12) {
                    TrainStatusChip(
                        title: "Deload suggested",
                        style: .warning,
                        accessibilityIdentifier: "trainDeloadBanner"
                    )
                    Text("Load is above your recent norm. Consider fewer working sets or capping RPE around 7.")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") {
                        dismissedDeloadWeek = currentISOWeekKey()
                        showDeloadBanner = false
                    }
                    .font(.metadataCaption.weight(.semibold))
                    .foregroundStyle(Color("Primary"))
                }
                .padding(12)
                .trainSurfaceCard()
            }

            if let busyDayChipTitle {
                TrainStatusChip(
                    title: busyDayChipTitle,
                    style: .warning,
                    accessibilityIdentifier: "busyDayChip"
                )
            }
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                startOrResumeWorkout()
            } label: {
                Label(
                    inProgressSession == nil ? "Start Workout" : "Continue Workout",
                    systemImage: inProgressSession == nil ? "play.fill" : "arrow.forward.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))
            .accessibilityIdentifier("startWorkoutButton")

            Button {
                showImportWorkout = true
            } label: {
                Label("Import Workout", systemImage: "doc.on.clipboard")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Color("Primary"))
            .accessibilityIdentifier("importWorkoutButton")
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrainSectionHeader(title: "Routines")

            if routines.isEmpty {
                ContentUnavailableView {
                    Label("No routines", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Create a routine or start an empty workout.")
                } actions: {
                    Button("New routine") {
                        showNewRoutine = true
                    }
                    .buttonStyle(.bordered)
                    .tint(Color("Primary"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(routines, id: \.persistentModelID) { routine in
                        routineRow(routine)
                    }
                }
            }
        }
    }

    private func routineRow(_ routine: Routine) -> some View {
        Button {
            startRoutine(routine)
        } label: {
            HStack(spacing: 12) {
                Text(routine.name)
                    .font(.body)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color("Primary"))
            }
            .padding(14)
            .trainSurfaceCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                editingRoutine = routine
            }
            Button("Delete", role: .destructive) {
                deleteRoutine(routine)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrainSectionHeader(title: "Recent")

            if recentSessions.isEmpty {
                ContentUnavailableView {
                    Label("No workouts yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Completed workouts appear here.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentSessions, id: \.persistentModelID) { session in
                        NavigationLink(value: TrainRoute.history(session.persistentModelID)) {
                            recentRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recentRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color("TextPrimary"))
                if let end = session.endTime {
                    Text(end.formatted(date: .abbreviated, time: .shortened))
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(14)
        .trainSurfaceCard(cornerRadius: 12)
    }

    private func inlineNotice(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.metadataCaption)
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainSurfaceCard(cornerRadius: 12)
    }

    @ViewBuilder
    private func routeDestination(_ route: TrainRoute) -> some View {
        switch route {
        case .activeWorkout(let sessionID):
            ActiveWorkoutContainerView(sessionID: sessionID)
        case .history(let id):
            if let session = resolveSession(id: id) {
                WorkoutHistoryDetailView(session: session)
            } else {
                ContentUnavailableView("Session not found", systemImage: "questionmark")
            }
        case .editRoutine:
            ContentUnavailableView("Routine editor unavailable", systemImage: "list.bullet")
        case .exerciseDetail(let detailRoute):
            ExerciseDetailView(route: detailRoute)
        }
    }

    private func resolveSession(id: PersistentIdentifier) -> WorkoutSession? {
        if let session = completedSessions.first(where: { $0.persistentModelID == id }) {
            return session
        }
        return try? modelContext.model(for: id) as? WorkoutSession
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
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
                watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
                Task {
                    await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
                }
                openActiveWorkout(sessionID: session.persistentModelID)
            } else {
                let session = try store.startEmpty()
                coordinator.refresh()
                watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
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
                watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
                Task {
                    await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
                }
                openActiveWorkout(sessionID: session.persistentModelID)
                return
            }
            let session = try store.start(from: routine)
            coordinator.refresh()
            watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
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

    private func reloadBusyDayChip() {
        Task {
            _ = await CalendarEventStore.shared.requestAccessIfNeeded()
            busyDayChipTitle = await CalendarContextBuilder().todayBusyChipTitle()
        }
    }

    private func reloadDeloadBanner() {
        let active = DeloadSuggestionReader.isDeloadActive(in: modelContext)
        showDeloadBanner = active && dismissedDeloadWeek != currentISOWeekKey()
    }

    private func currentISOWeekKey() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return ISOWeekIdentifier.current(calendar: calendar).keySegment
    }
}
