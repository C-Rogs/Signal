import Foundation

enum GoalType: String, Codable, CaseIterable, Sendable, Identifiable {
    case hypertrophy
    case strength
    case powerlifting
    case generalFitness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hypertrophy: "Hypertrophy"
        case .strength: "Strength"
        case .powerlifting: "Powerlifting"
        case .generalFitness: "General fitness"
        }
    }

    var oneLineDescription: String {
        switch self {
        case .hypertrophy:
            "Muscle size with moderate reps and controlled effort."
        case .strength:
            "Heavier loads, lower reps, leave one rep in reserve."
        case .powerlifting:
            "Max strength on the big lifts, grind when needed."
        case .generalFitness:
            "Balanced training for health and consistency."
        }
    }

    var defaultRIR: Int {
        switch self {
        case .hypertrophy: 2
        case .strength: 1
        case .powerlifting: 0
        case .generalFitness: 2
        }
    }
}
