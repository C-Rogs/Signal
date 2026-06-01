import SwiftData
import SwiftUI

@main
struct SignalApp: App {
    private let modelContainer: ModelContainer
    @State private var healthKitManager: HealthKitManager

    init() {
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
}
