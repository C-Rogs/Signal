import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct SignalApp: App {
    private let modelContainer: ModelContainer
    private let briefingNotificationDelegate: DailyBriefingNotificationDelegate
    @State private var healthKitManager: HealthKitManager
    @State private var unitPreferences = UnitPreferences.shared
    @State private var appPreferences = AppPreferences.shared
    @State private var trainPreferences = TrainPreferences.shared
    @State private var notificationPreferences = NotificationPreferences.shared
    @State private var recoveryPreferences = RecoveryPreferences.shared
    @State private var coachPreferences = CoachPreferences.shared
    @State private var liveWorkoutCoordinator = LiveWorkoutCoordinator()
    private let liveWorkoutWatchBridge = LiveWorkoutWatchBridge.shared

    init() {
        Self.applyDarkNavigationChrome()
        DailyBriefingScheduler.registerCategories()
        LiveWorkoutCoordinatorLaunchState.markProcessLaunched()
        do {
            let container = try SignalModelContainer.make()
            modelContainer = container
            CatalogBootstrap.runIfNeeded(modelContainer: container)
            DataQualityMigration.runIfNeeded(modelContainer: container)
            _ = DerivedMetricsService.shared
            _ = ReflectionEngine.shared
            _ = SetHRAttributionTrigger.shared
            WatchConnectivityService.shared.activate()
            WatchRecoveryPushCoordinator.shared.start()
            _healthKitManager = State(
                wrappedValue: HealthKitManager(modelContainer: container)
            )
            briefingNotificationDelegate = DailyBriefingNotificationDelegate(modelContainer: container)
            UNUserNotificationCenter.current().delegate = briefingNotificationDelegate
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(healthKitManager)
                .environment(unitPreferences)
                .environment(appPreferences)
                .environment(trainPreferences)
                .environment(notificationPreferences)
                .environment(recoveryPreferences)
                .environment(coachPreferences)
                .environment(liveWorkoutCoordinator)
                .environment(liveWorkoutWatchBridge)
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
