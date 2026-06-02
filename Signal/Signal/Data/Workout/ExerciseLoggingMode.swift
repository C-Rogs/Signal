import Foundation

enum ExerciseLoggingMode: Sendable, Equatable {
    case strength
    case cardio

    static func from(catalogEntry: ExerciseCatalog?) -> ExerciseLoggingMode {
        guard let catalogEntry, catalogEntry.movementPattern == .cardio else {
            return .strength
        }
        return .cardio
    }
}
