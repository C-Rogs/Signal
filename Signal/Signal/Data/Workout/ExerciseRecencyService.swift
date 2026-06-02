import Foundation
import SwiftData

private let exerciseRecencyLimit = 20

@MainActor
enum ExerciseRecencyService {
    static func recentCatalogIDs(in context: ModelContext, limit: Int = exerciseRecencyLimit) -> [PersistentIdentifier] {
        guard let exercises = try? context.fetch(FetchDescriptor<WorkoutExercise>()) else { return [] }

        var seen: Set<PersistentIdentifier> = []
        var ordered: [PersistentIdentifier] = []

        let sortedByRecency = exercises.sorted { lhs, rhs in
            let left = lhs.session?.startTime ?? .distantPast
            let right = rhs.session?.startTime ?? .distantPast
            if left != right { return left > right }
            return lhs.order > rhs.order
        }

        for exercise in sortedByRecency {
            guard let catalog = exercise.catalogEntry else { continue }
            let id = catalog.persistentModelID
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append(id)
            if ordered.count >= limit { break }
        }
        return ordered
    }
}
