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

    var routine: Routine?
    var catalogEntry: ExerciseCatalog?

    init(
        order: Int,
        exerciseTitleFallback: String? = nil,
        catalogEntry: ExerciseCatalog? = nil
    ) {
        self.order = order
        self.exerciseTitleFallback = exerciseTitleFallback
        self.catalogEntry = catalogEntry
    }
}
