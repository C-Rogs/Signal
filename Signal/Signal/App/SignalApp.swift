import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct SignalApp: App {
    @State private var modelContainer: ModelContainer?
    @State private var healthKitManager: HealthKitManager?
    @State private var briefingNotificationDelegate: DailyBriefingNotificationDelegate?
    @State private var bootstrapErrorMessage: String?
    @State private var bootstrapAttempt = 0
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
        _ = DerivedMetricsService.shared
        WatchConnectivityService.shared.activate()
        WatchRecoveryPushCoordinator.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            bootstrapRoot
                .task(id: bootstrapAttempt) {
                    await loadPersistedStoreIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var bootstrapRoot: some View {
        if let modelContainer, let healthKitManager {
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
                .modelContainer(modelContainer)
        } else if let bootstrapErrorMessage {
            AppLaunchFailureView(message: bootstrapErrorMessage) {
                self.bootstrapErrorMessage = nil
                bootstrapAttempt += 1
            }
        } else {
            AppLaunchShellView()
        }
    }

    @MainActor
    private func loadPersistedStoreIfNeeded() async {
        guard modelContainer == nil, bootstrapErrorMessage == nil else { return }
        await Task.yield()
        do {
            let container = try SignalModelContainer.make()
            CatalogBootstrap.runIfNeeded(modelContainer: container)
            DataQualityMigration.scheduleIfNeeded(modelContainer: container)
            _ = ReflectionEngine.shared
            _ = SetHRAttributionTrigger.shared
            let healthKit = HealthKitManager(modelContainer: container)
            let briefingDelegate = DailyBriefingNotificationDelegate(modelContainer: container)
            UNUserNotificationCenter.current().delegate = briefingDelegate
            liveWorkoutCoordinator.configure(modelContext: ModelContext(container))
            modelContainer = container
            healthKitManager = healthKit
            briefingNotificationDelegate = briefingDelegate
        } catch {
            bootstrapErrorMessage = error.localizedDescription
        }
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
