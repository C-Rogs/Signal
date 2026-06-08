import Foundation
import SwiftData

@Model
final class Routine {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class RoutineExercise {
    var order: Int
    var exerciseTitleFallback: String?
    var restDurationSeconds: Int = 90
    var autoStartRestOnSetComplete: Bool = true

    var routine: Routine?
    var catalogEntry: ExerciseCatalog?

    @Relationship(deleteRule: .cascade, inverse: \RoutinePresetSet.routineExercise)
    var presetSets: [RoutinePresetSet] = []

    init(
        order: Int,
        exerciseTitleFallback: String? = nil,
        catalogEntry: ExerciseCatalog? = nil,
        restDurationSeconds: Int = 90,
        autoStartRestOnSetComplete: Bool = true
    ) {
        self.order = order
        self.exerciseTitleFallback = exerciseTitleFallback
        self.catalogEntry = catalogEntry
        self.restDurationSeconds = restDurationSeconds
        self.autoStartRestOnSetComplete = autoStartRestOnSetComplete
    }

    var sortedPresetSets: [RoutinePresetSet] {
        presetSets.sorted { $0.setIndex < $1.setIndex }
    }

    var hasPresets: Bool {
        !presetSets.isEmpty
    }

    var presetSetCount: Int {
        presetSets.count
    }
}

extension Routine {
    var totalPresetSetCount: Int {
        exercises.reduce(0) { $0 + $1.presetSetCount }
    }

    var hasPresets: Bool {
        totalPresetSetCount > 0
    }
}
