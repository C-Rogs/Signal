import Foundation
import Observation

enum MassUnit: String, CaseIterable, Sendable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilograms: "Kilograms (kg)"
        case .pounds: "Pounds (lb)"
        }
    }

    var shortSymbol: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }
}

enum DistanceUnit: String, CaseIterable, Sendable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilometers: "Kilometers (km)"
        case .miles: "Miles (mi)"
        }
    }

    var shortSymbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        }
    }
}

@MainActor
@Observable
final class UnitPreferences {
    static let shared = UnitPreferences()

    var massUnit: MassUnit {
        didSet { persistMassUnit() }
    }

    var distanceUnit: DistanceUnit {
        didSet { persistDistanceUnit() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.massUnitKey),
           let stored = MassUnit(rawValue: raw)
        {
            massUnit = stored
        } else {
            massUnit = Self.localeDefaultMassUnit()
        }
        if let raw = defaults.string(forKey: Self.distanceUnitKey),
           let stored = DistanceUnit(rawValue: raw)
        {
            distanceUnit = stored
        } else {
            distanceUnit = Self.localeDefaultDistanceUnit()
        }
    }

    static func localeDefaultMassUnit() -> MassUnit {
        switch Locale.current.measurementSystem {
        case .us:
            .pounds
        default:
            .kilograms
        }
    }

    static func localeDefaultDistanceUnit() -> DistanceUnit {
        switch Locale.current.measurementSystem {
        case .us, .uk:
            .miles
        default:
            .kilometers
        }
    }

    func resetToLocaleDefaults() {
        massUnit = Self.localeDefaultMassUnit()
        distanceUnit = Self.localeDefaultDistanceUnit()
    }

    private func persistMassUnit() {
        defaults.set(massUnit.rawValue, forKey: Self.massUnitKey)
    }

    private func persistDistanceUnit() {
        defaults.set(distanceUnit.rawValue, forKey: Self.distanceUnitKey)
    }

    private static let massUnitKey = "signal.unitPreference.mass"
    private static let distanceUnitKey = "signal.unitPreference.distance"
}
