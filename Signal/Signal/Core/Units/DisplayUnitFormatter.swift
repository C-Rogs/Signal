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
}
