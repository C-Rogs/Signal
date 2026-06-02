import Foundation

enum DashboardChartValueStyle: Sendable {
    case hrv
    case restingHR
    case activeEnergy
    case sleepHours
    case bodyMass
    case steps
    case exerciseMinutes
    case nutritionCalories

    func formattedValue(_ value: Double, formatter: DisplayUnitFormatter) -> String {
        switch self {
        case .hrv:
            DashboardFormatting.hrv(value)
        case .restingHR:
            DashboardFormatting.heartRate(value)
        case .activeEnergy, .nutritionCalories:
            DashboardFormatting.calories(value)
        case .sleepHours:
            DashboardFormatting.sleep(value)
        case .bodyMass:
            DashboardFormatting.bodyMass(value, formatter: formatter)
        case .steps:
            DashboardFormatting.steps(value)
        case .exerciseMinutes:
            DashboardFormatting.minutes(value)
        }
    }

    func yAxisLabel(_ value: Double, formatter: DisplayUnitFormatter) -> String {
        switch self {
        case .activeEnergy, .nutritionCalories:
            if value >= 1000 {
                return "\(Int((value / 1000).rounded()))k"
            }
            return "\(Int(value.rounded()))"
        case .sleepHours:
            return String(format: "%.1f", value)
        case .bodyMass:
            let display = formatter.displayMassKg(value)
            return String(format: "%.0f", display)
        default:
            return "\(Int(value.rounded()))"
        }
    }
}
