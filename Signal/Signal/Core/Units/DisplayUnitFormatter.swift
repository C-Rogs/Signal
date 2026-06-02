import Foundation

struct DisplayUnitFormatter: Sendable {
    let massUnit: MassUnit
    let distanceUnit: DistanceUnit

    init(preferences: UnitPreferences) {
        massUnit = preferences.massUnit
        distanceUnit = preferences.distanceUnit
    }

    func formatMassKg(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        switch massUnit {
        case .kilograms:
            return String(format: "%.1f kg", kg)
        case .pounds:
            let pounds = kg * 2.204_622_621_8
            return String(format: "%.1f lb", pounds)
        }
    }

    func displayMassKg(_ kg: Double) -> Double {
        switch massUnit {
        case .kilograms:
            kg
        case .pounds:
            kg * 2.204_622_621_8
        }
    }

    func formatDistanceKm(_ km: Double?) -> String {
        guard let km else { return "—" }
        switch distanceUnit {
        case .kilometers:
            return String(format: "%.1f km", km)
        case .miles:
            let miles = km * 0.621_371_192_237_333_9
            return String(format: "%.1f mi", miles)
        }
    }

    func displayDistanceKm(_ km: Double) -> Double {
        switch distanceUnit {
        case .kilometers:
            km
        case .miles:
            km * 0.621_371_192_237_333_9
        }
    }

    func parseMassInputToKg(_ displayValue: Double) -> Double {
        switch massUnit {
        case .kilograms:
            displayValue
        case .pounds:
            displayValue / 2.204_622_621_8
        }
    }

    func parseMassInputToKg(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(normalized) else { return nil }
        return parseMassInputToKg(value)
    }

    func parseDistanceInputToKm(_ displayValue: Double) -> Double {
        switch distanceUnit {
        case .kilometers:
            displayValue
        case .miles:
            displayValue / 0.621_371_192_237_333_9
        }
    }

    func parseDistanceInputToKm(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(normalized) else { return nil }
        return parseDistanceInputToKm(value)
    }

    func displayMassInputKg(_ kg: Double?) -> String {
        guard let kg else { return "" }
        let display = displayMassKg(kg)
        if display.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", display)
        }
        return String(format: "%.1f", display)
    }

    func displayDistanceInputKm(_ km: Double?) -> String {
        guard let km else { return "" }
        let display = displayDistanceKm(km)
        if display.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", display)
        }
        return String(format: "%.1f", display)
    }
}
