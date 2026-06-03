import Foundation

enum WorkoutRPEScale {
    static let pickerValues: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    static let defaultValue: Double = 8

    static func compactLabel(for value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    static func clamp(_ value: Double) -> Double {
        min(10, max(6, value))
    }

    static func snapToPicker(_ value: Double) -> Double {
        let clamped = clamp(value)
        return pickerValues.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? defaultValue
    }

    static func effortTitle(for value: Double) -> String {
        switch value {
        case 10: "Maximum Effort"
        case 9.5: "Extremely Hard Effort"
        case 9: "Very Hard Effort"
        case 8.5: "Hard Effort"
        case 8: "Hard Effort"
        case 7.5: "Moderate-Hard Effort"
        case 7: "Moderate Effort"
        case 6.5: "Moderate-Light Effort"
        default: "Light Effort"
        }
    }

    static func effortDetail(for value: Double) -> String {
        switch value {
        case 10: "Could not have done another rep"
        case 9.5: "Could have done 0 more reps"
        case 9: "Could have definitely done 1 more rep"
        case 8.5: "Could have done 1 to 2 more reps"
        case 8: "Could have definitely done 2 more reps"
        case 7.5: "Could have done 2 to 3 more reps"
        case 7: "Could have done 3 more reps"
        case 6.5: "Could have done 3 to 4 more reps"
        default: "Could have done 4 or more reps"
        }
    }
}
