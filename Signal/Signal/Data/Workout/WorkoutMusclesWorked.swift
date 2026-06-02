import Foundation
import SwiftData

enum WorkoutMusclesWorked {
    static func muscles(for session: WorkoutSession) -> [Muscle] {
        var result: Set<Muscle> = []
        for exercise in session.exercises {
            if let catalog = exercise.catalogEntry {
                result.formUnion(catalog.primaryMuscles)
                result.formUnion(catalog.secondaryMuscles)
            }
        }
        if result.isEmpty {
            return []
        }
        return Muscle.allCases
            .filter { $0 != .fullBody && result.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
    }
}
