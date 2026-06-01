import Foundation
import os

enum AppleHealthRecordTypes {
    static let tier1: Set<String> = [
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKCategoryTypeIdentifierSleepAnalysis",
    ]

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
        guard let unit, !unit.isEmpty else {
            Log.import.warning("resting HR record missing unit; assuming count/min")
            return value
        }
        let normalized = unit.lowercased()
        if normalized == "count/min" {
            return value
        }
        Log.import.warning("unexpected resting HR unit=\(unit, privacy: .public); skipped sample")
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
        default:
            break
        }
    }

    func logDistinctSources() {
        Log.import.info("distinct sourceName HRV count=\(hrv.count, privacy: .public) sources=\(Self.sortedList(hrv), privacy: .public)")
        Log.import.info("distinct sourceName restingHR count=\(restingHR.count, privacy: .public) sources=\(Self.sortedList(restingHR), privacy: .public)")
        Log.import.info("distinct sourceName activeEnergy count=\(activeEnergy.count, privacy: .public) sources=\(Self.sortedList(activeEnergy), privacy: .public)")
        Log.import.info("distinct sourceName sleep count=\(sleep.count, privacy: .public) sources=\(Self.sortedList(sleep), privacy: .public)")
    }

    private static func sortedList(_ names: Set<String>) -> String {
        names.sorted().joined(separator: " | ")
    }
}
