import SwiftData
import SwiftUI

@main
struct SignalApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try SignalModelContainer.make()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
