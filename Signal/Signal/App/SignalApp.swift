import SwiftData
import SwiftUI
import UIKit

@main
struct SignalApp: App {
    private let modelContainer: ModelContainer
    @State private var healthKitManager: HealthKitManager
    @State private var unitPreferences = UnitPreferences.shared
    @State private var trainPreferences = TrainPreferences.shared
    @State private var liveWorkoutCoordinator = LiveWorkoutCoordinator()

    init() {
        Self.applyDarkNavigationChrome()
        LiveWorkoutCoordinatorLaunchState.markProcessLaunched()
        do {
            let container = try SignalModelContainer.make()
            modelContainer = container
            CatalogBootstrap.runIfNeeded(modelContainer: container)
            DataQualityMigration.runIfNeeded(modelContainer: container)
            _ = DerivedMetricsService.shared
            _ = ReflectionEngine.shared
            _ = SetHRAttributionTrigger.shared
            _healthKitManager = State(
                wrappedValue: HealthKitManager(modelContainer: container)
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(healthKitManager)
                .environment(unitPreferences)
                .environment(trainPreferences)
                .environment(liveWorkoutCoordinator)
        }
        .modelContainer(modelContainer)
    }

    private static func applyDarkNavigationChrome() {
        let navBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
        let navTitle = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = navBackground
        nav.titleTextAttributes = [.foregroundColor: navTitle]
        nav.largeTitleTextAttributes = [.foregroundColor: navTitle]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = nav
        bar.scrollEdgeAppearance = nav
        bar.compactAppearance = nav
        bar.tintColor = UIColor(named: "Primary")
    }
}
