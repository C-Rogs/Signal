import SwiftData

enum SignalModelContainer {
    static let schema = Schema([
        DailyMetric.self,
        AppleWorkout.self,
        RecoverySnapshot.self,
        SyncAnchor.self,
        HealthVector.self,
        WorkoutSession.self,
        WorkoutExercise.self,
        SetEntry.self,
    ])

    static func make(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
