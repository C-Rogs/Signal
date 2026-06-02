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
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = .black
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
