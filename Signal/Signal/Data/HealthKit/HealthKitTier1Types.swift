import Foundation
import HealthKit

enum HealthKitTier1Kind: String, CaseIterable, Sendable {
    case heartRateVariabilitySDNN
    case restingHeartRate
    case activeEnergyBurned
    case sleepAnalysis

    var sampleType: HKSampleType {
        switch self {
        case .heartRateVariabilitySDNN:
            HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate:
            HKQuantityType(.restingHeartRate)
        case .activeEnergyBurned:
            HKQuantityType(.activeEnergyBurned)
        case .sleepAnalysis:
            HKCategoryType(.sleepAnalysis)
        }
    }

    var anchorTypeIdentifier: String {
        sampleType.identifier
    }

    static var readObjectTypes: Set<HKObjectType> {
        Set(allCases.map(\.sampleType))
    }
}

enum HealthKitSyncLimits {
    static let lookbackDays = 120
}
