import Foundation
import os

enum AppleHealthRecordTypes {
    static let tier1: Set<String> = [
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKCategoryTypeIdentifierSleepAnalysis",
        "HKQuantityTypeIdentifierBodyMass",
        "HKQuantityTypeIdentifierVO2Max",
        "HKQuantityTypeIdentifierRespiratoryRate",
        "HKQuantityTypeIdentifierOxygenSaturation",
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierStepCount",
        "HKQuantityTypeIdentifierBasalEnergyBurned",
        "HKQuantityTypeIdentifierBodyFatPercentage",
        "HKQuantityTypeIdentifierLeanBodyMass",
        "HKQuantityTypeIdentifierWalkingHeartRateAverage",
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierPhysicalEffort",
        "HKQuantityTypeIdentifierTimeInDaylight",
        "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances",
        "HKCategoryTypeIdentifierAppleStandHour",
    ]

    // Additional HK dietary quantity types exist; V1 keeps this macro set only.
    static let nutritionTypes: Set<String> = [
        "HKQuantityTypeIdentifierDietaryEnergyConsumed",
        "HKQuantityTypeIdentifierDietaryProtein",
        "HKQuantityTypeIdentifierDietaryCarbohydrates",
        "HKQuantityTypeIdentifierDietaryFatTotal",
        "HKQuantityTypeIdentifierDietaryFatSaturated",
        "HKQuantityTypeIdentifierDietaryFiber",
        "HKQuantityTypeIdentifierDietarySugar",
        "HKQuantityTypeIdentifierDietarySodium",
    ]

    static let runningMechanicTypes: Set<String> = [
        "HKQuantityTypeIdentifierRunningPower",
        "HKQuantityTypeIdentifierRunningStrideLength",
        "HKQuantityTypeIdentifierRunningVerticalOscillation",
        "HKQuantityTypeIdentifierRunningGroundContactTime",
        "HKQuantityTypeIdentifierRunningSpeed",
    ]

    static let appleStandHourStood = "HKCategoryValueAppleStandHourStood"

    static let legacyAsleep = "HKCategoryValueSleepAnalysisAsleep"

    static let granularAsleep: Set<String> = [
        "HKCategoryValueSleepAnalysisAsleepCore",
        "HKCategoryValueSleepAnalysisAsleepDeep",
        "HKCategoryValueSleepAnalysisAsleepREM",
        "HKCategoryValueSleepAnalysisAsleepUnspecified",
    ]

    static func isAsleepCategoryValue(_ value: String) -> Bool {
        value == legacyAsleep || granularAsleep.contains(value)
    }

    static func isGranularAsleep(_ value: String) -> Bool {
        granularAsleep.contains(value)
    }

    static func isLegacyAsleep(_ value: String) -> Bool {
        value == legacyAsleep
    }
}

enum AppleHealthUnitNormalizer {
    private static let kilojoulesPerKilocalorie = 4.184

    static func normalizedHRV(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            Log.import.warning("HRV record missing unit; assuming ms")
            return value
        }
        let normalized = unit.lowercased()
        if normalized == "ms" {
            return value
        }
        Log.import.warning("unexpected HRV unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedRestingHR(value: Double, unit: String?) -> Double? {
        normalizedHeartRate(value: value, unit: unit)
    }

    static func normalizedHeartRate(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            Log.import.warning("heart rate record missing unit; assuming count/min")
            return value
        }
        let normalized = unit.lowercased()
        if normalized == "count/min" {
            return value
        }
        Log.import.warning("unexpected heart rate unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedActiveEnergyKcal(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            Log.import.warning("active energy record missing unit; skipped sample")
            return nil
        }
        let normalized = unit.lowercased()
        switch normalized {
        case "kcal":
            return value
        case "kj":
            return value / kilojoulesPerKilocalorie
        default:
            Log.import.warning("unexpected active energy unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
    }

    static func normalizedBasalEnergyKcal(value: Double, unit: String?) -> Double? {
        normalizedActiveEnergyKcal(value: value, unit: unit)
    }

    static func normalizedBodyMassKg(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            Log.import.warning("body mass record missing unit; assuming kg")
            return value
        }
        switch unit.lowercased() {
        case "kg":
            return value
        case "lb", "lbs":
            return value * 0.45359237
        default:
            Log.import.warning("unexpected body mass unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
    }

    static func normalizedVO2Max(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        let normalized = unit.lowercased()
        if normalized.contains("ml") || normalized == "ml/kg*min" || normalized == "ml/kg/min" {
            return value
        }
        Log.import.warning("unexpected VO2 max unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedRespiratoryRate(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        if unit.lowercased() == "count/min" {
            return value
        }
        Log.import.warning("unexpected respiratory rate unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedBloodOxygenPct(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value <= 1 ? value * 100 : value
        }
        switch unit.lowercased() {
        case "%":
            return value
        default:
            if value <= 1 {
                return value * 100
            }
            return value
        }
    }

    static func normalizedWristTemperatureDeltaC(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        if unit.lowercased() == "degc" || unit.lowercased() == "c" {
            return value
        }
        Log.import.warning("unexpected wrist temperature unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedStepCount(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        if unit.lowercased() == "count" {
            return value
        }
        Log.import.warning("unexpected step count unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedBodyFatPercentage(value: Double, unit: String?) -> Double? {
        let pct = DailyMetricAggregator.normalizedBodyFatPercentage(value: value, unit: unit)
        guard pct.isFinite, pct > 0 else { return nil }
        return pct
    }

    static func normalizedLeanBodyMassKg(value: Double, unit: String?) -> Double? {
        normalizedBodyMassKg(value: value, unit: unit)
    }

    static func normalizedMinutes(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        switch unit.lowercased() {
        case "min", "minute", "minutes":
            return value
        case "s", "sec", "second", "seconds":
            return value / 60
        default:
            Log.import.warning("unexpected duration unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
    }

    static func normalizedPhysicalEffort(value: Double, unit: String?) -> Double? {
        guard value.isFinite else { return nil }
        if let unit, !unit.isEmpty {
            let normalized = unit.lowercased()
            if normalized.contains("kcal") || normalized.contains("kg") {
                return value
            }
            Log.import.warning("unexpected physical effort unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
        return value
    }

    static func normalizedGrams(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        switch unit.lowercased() {
        case "g", "gram", "grams":
            return value
        default:
            Log.import.warning("unexpected mass unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
    }

    static func normalizedMilligrams(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        switch unit.lowercased() {
        case "mg", "milligram", "milligrams":
            return value
        case "g", "gram", "grams":
            return value * 1000
        default:
            Log.import.warning("unexpected sodium unit=\(unit, privacy: .public); skipped sample")
            return nil
        }
    }

    static func normalizedBloodPressureMmHg(value: Double, unit: String?) -> Double? {
        guard let unit, !unit.isEmpty else {
            return value
        }
        if unit.lowercased() == "mmhg" {
            return value
        }
        Log.import.warning("unexpected blood pressure unit=\(unit, privacy: .public); skipped sample")
        return nil
    }

    static func normalizedRunningSpeedKmh(value: Double, unit: String?) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        guard let unit, !unit.isEmpty else { return value }
        let normalized = unit.lowercased()
        if normalized == "km/hr" || normalized == "km/h" {
            return value
        }
        if normalized == "m/s" || normalized == "mps" {
            return value * 3.6
        }
        Log.import.warning("unexpected running speed unit=\(unit, privacy: .public); skipped sample")
        return nil
    }
}

enum AppleHealthDateParser {
    private static let primary: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    private static let fallback: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
        return formatter
    }()

    private static var loggedFallback = false

    static func parse(_ string: String) -> Date? {
        if let date = primary.date(from: string) {
            return date
        }
        if let date = fallback.date(from: string) {
            if !loggedFallback {
                loggedFallback = true
                Log.import.info("using fallback date format for some export timestamps")
            }
            return date
        }
        return nil
    }

    static func resetForTesting() {
        loggedFallback = false
    }
}

struct AppleHealthSourceNames: Sendable {
    private(set) var hrv: Set<String> = []
    private(set) var restingHR: Set<String> = []
    private(set) var activeEnergy: Set<String> = []
    private(set) var sleep: Set<String> = []
    private(set) var bodyMass: Set<String> = []
    private(set) var vo2Max: Set<String> = []
    private(set) var respiratory: Set<String> = []
    private(set) var oxygen: Set<String> = []
    private(set) var wristTemp: Set<String> = []
    private(set) var heartRate: Set<String> = []
    private(set) var steps: Set<String> = []
    private(set) var basalEnergy: Set<String> = []

    mutating func record(type: String, sourceName: String?) {
        guard let sourceName, !sourceName.isEmpty else { return }
        switch type {
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            hrv.insert(sourceName)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            restingHR.insert(sourceName)
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            activeEnergy.insert(sourceName)
        case "HKCategoryTypeIdentifierSleepAnalysis":
            sleep.insert(sourceName)
        case "HKQuantityTypeIdentifierBodyMass":
            bodyMass.insert(sourceName)
        case "HKQuantityTypeIdentifierVO2Max":
            vo2Max.insert(sourceName)
        case "HKQuantityTypeIdentifierRespiratoryRate":
            respiratory.insert(sourceName)
        case "HKQuantityTypeIdentifierOxygenSaturation":
            oxygen.insert(sourceName)
        case "HKQuantityTypeIdentifierAppleSleepingWristTemperature":
            wristTemp.insert(sourceName)
        case "HKQuantityTypeIdentifierHeartRate":
            heartRate.insert(sourceName)
        case "HKQuantityTypeIdentifierStepCount":
            steps.insert(sourceName)
        case "HKQuantityTypeIdentifierBasalEnergyBurned":
            basalEnergy.insert(sourceName)
        default:
            break
        }
    }

    func logDistinctSources() {
        Log.import.info("distinct sourceName HRV count=\(hrv.count, privacy: .public) sources=\(Self.sortedList(hrv), privacy: .public)")
        Log.import.info("distinct sourceName restingHR count=\(restingHR.count, privacy: .public) sources=\(Self.sortedList(restingHR), privacy: .public)")
        Log.import.info("distinct sourceName activeEnergy count=\(activeEnergy.count, privacy: .public) sources=\(Self.sortedList(activeEnergy), privacy: .public)")
        Log.import.info("distinct sourceName sleep count=\(sleep.count, privacy: .public) sources=\(Self.sortedList(sleep), privacy: .public)")
        Log.import.info("distinct sourceName bodyMass count=\(bodyMass.count, privacy: .public) sources=\(Self.sortedList(bodyMass), privacy: .public)")
        Log.import.info("distinct sourceName vo2Max count=\(vo2Max.count, privacy: .public) sources=\(Self.sortedList(vo2Max), privacy: .public)")
        Log.import.info("distinct sourceName respiratory count=\(respiratory.count, privacy: .public) sources=\(Self.sortedList(respiratory), privacy: .public)")
        Log.import.info("distinct sourceName oxygen count=\(oxygen.count, privacy: .public) sources=\(Self.sortedList(oxygen), privacy: .public)")
        Log.import.info("distinct sourceName wristTemp count=\(wristTemp.count, privacy: .public) sources=\(Self.sortedList(wristTemp), privacy: .public)")
        Log.import.info("distinct sourceName heartRate count=\(heartRate.count, privacy: .public) sources=\(Self.sortedList(heartRate), privacy: .public)")
        Log.import.info("distinct sourceName steps count=\(steps.count, privacy: .public) sources=\(Self.sortedList(steps), privacy: .public)")
        Log.import.info("distinct sourceName basalEnergy count=\(basalEnergy.count, privacy: .public) sources=\(Self.sortedList(basalEnergy), privacy: .public)")
    }

    private static func sortedList(_ names: Set<String>) -> String {
        names.sorted().joined(separator: " | ")
    }
}
