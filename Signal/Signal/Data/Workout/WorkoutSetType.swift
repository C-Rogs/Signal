import Foundation

enum WorkoutSetType: String, CaseIterable, Sendable, Identifiable {
    case warmup
    case normal
    case drop
    case failure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warmup: "Warmup"
        case .normal: "Normal"
        case .drop: "Drop"
        case .failure: "Failure"
        }
    }

    var storageValue: String { rawValue }

    init?(storageValue: String) {
        let normalized = storageValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "warmup", "warm_up":
            self = .warmup
        case "normal":
            self = .normal
        case "drop", "drop_set":
            self = .drop
        case "failure", "fail":
            self = .failure
        default:
            return nil
        }
    }
}
