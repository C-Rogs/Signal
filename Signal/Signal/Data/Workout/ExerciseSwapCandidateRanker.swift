import Foundation
import SwiftData

struct ExerciseSwapCandidate {
    let catalogEntry: ExerciseCatalog
    let score: Int
}

enum ExerciseSwapConstraintParser {
    private static let equipmentKeywords: [(String, ExerciseEquipment)] = [
        ("barbell", .barbell),
        ("dumbbell", .dumbbell),
        ("machine", .machine),
        ("cable", .cable),
        ("smith", .smith),
        ("kettlebell", .kettlebell),
        ("rack", .barbell),
    ]

    private static let occupancyKeywords = ["occupied", "taken", "busy", "in use", "not free"]

    static func excludedEquipment(from constraint: String) -> Set<ExerciseEquipment> {
        let normalized = constraint.lowercased()
        var excluded: Set<ExerciseEquipment> = []

        for (keyword, equipment) in equipmentKeywords where normalized.contains(keyword) {
            excluded.insert(equipment)
        }

        if normalized.contains("bench"),
           occupancyKeywords.contains(where: { normalized.contains($0) })
        {
            excluded.insert(.barbell)
            excluded.insert(.smith)
        }

        return excluded
    }
}

@MainActor
enum ExerciseSwapCandidateRanker {
    static let maxCandidates = 8

    static func rank(
        source: WorkoutExercise,
        constraint: String,
        catalog: [ExerciseCatalog],
        in context: ModelContext
    ) -> [ExerciseSwapCandidate] {
        guard let sourceCatalog = source.catalogEntry else {
            return fallbackByTitle(source: source, catalog: catalog, in: context)
        }

        let sourceMuscles = Set(sourceCatalog.primaryMuscles)
        let sourcePattern = sourceCatalog.movementPattern
        let excludedEquipment = ExerciseSwapConstraintParser.excludedEquipment(from: constraint)
        let historyIDs = loggedExerciseIDs(in: context)

        let filtered = catalog.filter { entry in
            guard entry.canonicalName != sourceCatalog.canonicalName else { return false }
            guard entry.movementPattern == sourcePattern else { return false }
            guard !Set(entry.primaryMuscles).isDisjoint(with: sourceMuscles) else { return false }
            guard !excludedEquipment.contains(entry.equipment) else { return false }
            return true
        }

        let scored = filtered.map { entry -> ExerciseSwapCandidate in
            var score = 0
            if historyIDs.contains(entry.canonicalName) {
                score += 30
            }
            if entry.isPickerDefault {
                score += 20
            }
            switch entry.equipment {
            case .dumbbell, .machine, .cable:
                if excludedEquipment.contains(.barbell) || excludedEquipment.contains(.smith) {
                    score += 15
                }
            default:
                break
            }
            return ExerciseSwapCandidate(catalogEntry: entry, score: score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.catalogEntry.canonicalName < rhs.catalogEntry.canonicalName
            }
            .prefix(maxCandidates)
            .map { $0 }
    }

    @MainActor
    private static func loggedExerciseIDs(in context: ModelContext) -> Set<String> {
        let rows = (try? ExerciseProgressStore.fetchRecentDistinctExercises(limit: 80, in: context)) ?? []
        return Set(rows.map(\.exerciseID))
    }

    @MainActor
    private static func fallbackByTitle(
        source: WorkoutExercise,
        catalog: [ExerciseCatalog],
        in context: ModelContext
    ) -> [ExerciseSwapCandidate] {
        let normalized = ExerciseTitleNormalizer.normalize(source.exerciseTitle)
        let historyIDs = loggedExerciseIDs(in: context)
        let matches = catalog.filter { entry in
            guard ExerciseTitleNormalizer.normalize(entry.canonicalName) != normalized else { return false }
            return entry.canonicalName.lowercased().contains("press")
                || entry.canonicalName.lowercased().contains("row")
        }
        return matches
            .map { entry in
                var score = 0
                if historyIDs.contains(entry.canonicalName) { score += 20 }
                if entry.isPickerDefault { score += 10 }
                return ExerciseSwapCandidate(catalogEntry: entry, score: score)
            }
            .sorted { $0.score > $1.score }
            .prefix(maxCandidates)
            .map { $0 }
    }
}
