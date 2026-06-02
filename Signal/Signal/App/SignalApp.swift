import SwiftData
import SwiftUI
import UIKit

@main
struct SignalApp: App {
    private let modelContainer: ModelContainer
    @State private var healthKitManager: HealthKitManager

    init() {
        Self.applyDarkNavigationChrome()
        do {
            let container = try SignalModelContainer.make()
            modelContainer = container
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
