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
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
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
    var body: some View {
        NavigationStack {
            DashboardView()
        }
    }
}

private struct TrainTabRoot: View {
    var body: some View {
        NavigationStack {
            TrainPlaceholderView()
        }
    }
}

private struct CoachTabRoot: View {
    var body: some View {
        NavigationStack {
            CoachPlaceholderView()
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
        .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
