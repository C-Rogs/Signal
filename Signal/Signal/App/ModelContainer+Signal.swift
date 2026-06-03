import Foundation
import os
import SwiftData

enum SignalModelContainer {
    static let schema = Schema([
        DailyMetric.self,
        DailyNutrition.self,
        AppleWorkout.self,
        RecoverySnapshot.self,
        SyncAnchor.self,
        HealthVector.self,
        WorkoutSession.self,
        WorkoutExercise.self,
        SetEntry.self,
        ExerciseCatalog.self,
        Routine.self,
        RoutineExercise.self,
        WellnessEntry.self,
        UserProfile.self,
        BodyweightEntry.self,
        TrainingGoal.self,
        ExerciseProgress.self,
        DataQualityFlag.self,
    ])

    static func make(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !inMemoryOnly else { throw error }
            Log.recovery.error(
                "ModelContainer load failed; resetting persistent store: \(String(describing: error), privacy: .public)"
            )
            try removeStoreFiles(for: configuration)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    private static func removeStoreFiles(for configuration: ModelConfiguration) throws {
        let storeURL = configuration.url
        let fileManager = FileManager.default
        let related = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
        for url in related where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
