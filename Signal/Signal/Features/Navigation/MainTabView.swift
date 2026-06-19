import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case coach
    case profile
}

private struct WellnessSheetSession: Identifiable {
    let session: WorkoutSession

    var id: PersistentIdentifier {
        session.persistentModelID
    }
}

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @State private var selectedTab: AppTab = .dashboard
    @State private var isLaunchShellReady = false

    private var showsWorkoutBanner: Bool {
        coordinator.activeSession != nil && !coordinator.isViewingActiveWorkout
    }

    private var tabBottomAccessoryVisible: Bool {
        isLaunchShellReady && showsWorkoutBanner && scenePhase == .active
    }

    private var resolvedWellnessSession: WellnessSheetSession? {
        guard let sessionID = coordinator.pendingWellnessSessionID,
              let session = modelContext.model(for: sessionID) as? WorkoutSession
        else {
            return nil
        }
        return WellnessSheetSession(session: session)
    }

    var body: some View {
        tabShell
            .onChange(of: coordinator.pendingTrainRoute) { _, route in
                if case .activeWorkout = route {
                    selectedTab = .train
                }
            }
            .onAppear {
                coordinator.configure(modelContext: modelContext)
                markLaunchShellReadyIfNeeded()
            }
            .onChange(of: showsWorkoutBanner) { _, _ in
                markLaunchShellReadyIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                TrainWorkoutDiagnostics.record(
                    "mainTab scenePhase=\(phase) viewingWorkout=\(coordinator.isViewingActiveWorkout) banner=\(showsWorkoutBanner) accessoryVisible=\(tabBottomAccessoryVisible) branch=\(accessoryBranchLabel)"
                )
                if phase == .active {
                    coordinator.configure(modelContext: modelContext)
                    coordinator.refresh()
                }
            }
            .onChange(of: coordinator.pendingWellnessSessionID) { _, sessionID in
                guard sessionID != nil, resolvedWellnessSession == nil else { return }
                coordinator.dismissWellness()
            }
            .onChange(of: selectedTab) { oldTab, tab in
                if oldTab != tab {
                    AppFeedback.shared.play(.tabChange)
                }
                if tab != .train, coordinator.activeSession == nil, coordinator.presentedWorkoutSessionID == nil {
                    coordinator.isViewingActiveWorkout = false
                }
                if tab == .dashboard {
                    NotificationCenter.default.post(name: .signalDashboardBecameSelected, object: nil)
                }
            }
            .sheet(item: wellnessSheetItem) { item in
                TrainWellnessFinishSheet(session: item.session, healthKitManager: healthKitManager)
            }
    }

    private var wellnessSheetItem: Binding<WellnessSheetSession?> {
        Binding(
            get: { resolvedWellnessSession },
            set: { item in
                if item == nil {
                    if let sessionID = coordinator.pendingWellnessSessionID,
                       let session = modelContext.model(for: sessionID) as? WorkoutSession
                    {
                        ExerciseProgressStore.recordFinishedSession(session, in: modelContext)
                    }
                    coordinator.dismissWellness()
                }
            }
        )
    }

    private var accessoryBranchLabel: String {
        isLaunchShellReady && showsWorkoutBanner ? "attached" : "plain"
    }

    private func markLaunchShellReadyIfNeeded() {
        guard !isLaunchShellReady else { return }
        if showsWorkoutBanner {
            isLaunchShellReady = true
        } else {
            Task { @MainActor in
                await Task.yield()
                isLaunchShellReady = true
            }
        }
    }

    @ViewBuilder
    private var tabShell: some View {
        let tabs = tabViewCore
        if isLaunchShellReady, showsWorkoutBanner {
            tabs.tabViewBottomAccessory {
                LiveWorkoutBanner(selectedTab: $selectedTab)
                    .opacity(tabBottomAccessoryVisible ? 1 : 0)
                    .allowsHitTesting(tabBottomAccessoryVisible)
                    .accessibilityHidden(!tabBottomAccessoryVisible)
            }
        } else {
            tabs
        }
    }

    private var tabViewCore: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.dashboard) {
                DashboardTabRoot()
            }
            Tab("Train", systemImage: "figure.strengthtraining.traditional", value: AppTab.train) {
                TrainTabRoot()
            }
            Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) {
                CoachTabRoot()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileTabRoot()
            }
        }
        .tint(Color("Primary"))
        .toolbarBackground(tabBarBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var tabBarBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

private struct DashboardTabRoot: View {
    @State private var path: [DashboardDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(navigationPath: $path)
                .navigationDestination(for: DashboardDestination.self) { destination in
                    switch destination {
                    case .insights:
                        InsightsView()
                    }
                }
        }
    }
}

private struct TrainTabRoot: View {
    var body: some View {
        TrainHomeView()
    }
}

private struct CoachTabRoot: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ChatView(modelContainer: modelContext.container)
        }
    }
}

private struct ProfileTabRoot: View {
    var body: some View {
        NavigationStack {
            ProfileView()
        }
    }
}

#Preview("Tabs") {
    MainTabView()
        .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
        .environment(UnitPreferences.shared)
        .environment(LiveWorkoutCoordinator())
        .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
