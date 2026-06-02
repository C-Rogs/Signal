import Foundation

enum MuscleMapper {
    static func muscles(
        primary datasetPrimary: [String],
        secondary datasetSecondary: [String],
        exerciseName: String
    ) -> (primary: [Muscle], secondary: [Muscle]) {
        let primary = datasetPrimary.flatMap { mapDatasetMuscle($0, exerciseName: exerciseName) }
        let secondary = datasetSecondary.flatMap { mapDatasetMuscle($0, exerciseName: exerciseName) }
        let primaryUnique = orderedUnique(primary)
        let secondaryUnique = orderedUnique(secondary.filter { !primaryUnique.contains($0) })
        return (primaryUnique, secondaryUnique)
    }

    private static func mapDatasetMuscle(_ raw: String, exerciseName: String) -> [Muscle] {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nameLower = exerciseName.lowercased()
        switch key {
        case "quadriceps":
            return [.quads]
        case "hamstrings":
            return [.hamstrings]
        case "glutes":
            return [.glutes]
        case "calves":
            return [.calves]
        case "chest":
            return [.chest]
        case "lats":
            return [.lats]
        case "middle back":
            return [.upperBack]
        case "traps":
            return [.traps]
        case "lower back":
            return [.lowerBack]
        case "biceps":
            return [.biceps]
        case "triceps":
            return [.triceps]
        case "forearms":
            return [.forearms]
        case "abdominals":
            if nameLower.contains("oblique") || nameLower.contains("side bend") {
                return [.obliques]
            }
            return [.abs]
        case "abductors", "adductors":
            return [.glutes]
        case "neck":
            return [.traps]
        case "shoulders":
            return mapShouldersFromDatasetName(nameLower)
        default:
            return []
        }
    }

    private static func mapShouldersFromDatasetName(_ nameLower: String) -> [Muscle] {
        if nameLower.contains("rear") || nameLower.contains("reverse fly") {
            return [.rearDelts]
        }
        if nameLower.contains("lateral") || nameLower.contains("side raise") {
            return [.sideDelts]
        }
        if nameLower.contains("front raise") {
            return [.frontDelts]
        }
        if nameLower.contains("upright row") {
            return [.traps, .sideDelts]
        }
        if nameLower.contains("shrug") {
            return [.traps]
        }
        if nameLower.contains("overhead") || nameLower.contains("military") || nameLower.contains("shoulder press") {
            return [.frontDelts, .sideDelts]
        }
        return [.frontDelts]
    }

    private static func orderedUnique(_ muscles: [Muscle]) -> [Muscle] {
        var seen = Set<Muscle>()
        var result: [Muscle] = []
        for muscle in muscles where seen.insert(muscle).inserted {
            result.append(muscle)
        }
        return result
    }
}
