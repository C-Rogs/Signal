import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case coach
    case profile
}

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @State private var selectedTab: AppTab = .dashboard

    private var showsWorkoutBanner: Bool {
        coordinator.activeSession != nil && !coordinator.isViewingActiveWorkout
    }

    private var tabBottomAccessoryEnabled: Bool {
        showsWorkoutBanner && scenePhase == .active
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
            }
            .onChange(of: scenePhase) { _, phase in
                TrainWorkoutDiagnostics.record(
                    "mainTab scenePhase=\(phase) viewingWorkout=\(coordinator.isViewingActiveWorkout) banner=\(showsWorkoutBanner) accessory=\(tabBottomAccessoryEnabled)"
                )
                if phase == .active {
                    coordinator.configure(modelContext: modelContext)
                    coordinator.refresh()
                }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab != .train, coordinator.activeSession == nil {
                    coordinator.isViewingActiveWorkout = false
                }
                if tab == .dashboard {
                    NotificationCenter.default.post(name: .signalDashboardBecameSelected, object: nil)
                }
            }
            .sheet(isPresented: wellnessSheetPresented) {
                TrainWellnessFinishSheet(healthKitManager: healthKitManager)
            }
    }

    private var wellnessSheetPresented: Binding<Bool> {
        Binding(
            get: { coordinator.pendingWellnessSessionID != nil },
            set: { isPresented in
                if !isPresented {
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

    @ViewBuilder
    private var tabShell: some View {
        let tabs = tabViewCore
        if #available(iOS 26.1, *) {
            tabs.tabViewBottomAccessory(isEnabled: tabBottomAccessoryEnabled) {
                LiveWorkoutBanner(selectedTab: $selectedTab)
            }
        } else if tabBottomAccessoryEnabled {
            tabs.tabViewBottomAccessory {
                LiveWorkoutBanner(selectedTab: $selectedTab)
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
