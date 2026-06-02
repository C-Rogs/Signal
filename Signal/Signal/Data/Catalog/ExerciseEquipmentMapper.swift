import Foundation

enum ExerciseEquipmentMapper {
    static func map(datasetEquipment: String?, exerciseName: String) -> ExerciseEquipment {
        let nameLower = exerciseName.lowercased()
        if nameLower.contains("smith") {
            return .smith
        }
        guard let raw = datasetEquipment?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return .other
        }
        switch raw {
        case "body only":
            return .bodyweight
        case "barbell", "e-z curl bar":
            return .barbell
        case "dumbbell":
            return .dumbbell
        case "machine":
            return .machine
        case "cable":
            return .cable
        case "kettlebells":
            return .kettlebell
        case "bands":
            return .band
        default:
            return .other
        }
    }

    static func hevyDisplayName(for equipment: ExerciseEquipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .smith: "Smith Machine"
        case .other: "Other"
        }
    }
}
