import Foundation
import os
import SwiftData

@MainActor
enum CatalogBootstrap {
    static func runIfNeeded(modelContainer: ModelContainer) {
        Task { @MainActor in
            let context = ModelContext(modelContainer)
            do {
                _ = try ExerciseCatalogSeeder.seedIfNeeded(in: context)
                _ = try CatalogLinkService.linkAllWorkoutExercises(in: context)
            } catch {
                Log.catalog.error("catalog bootstrap failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
