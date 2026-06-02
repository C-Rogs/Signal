import Foundation
import HealthKit

enum HealthKitTier1Kind: String, CaseIterable, Sendable {
    case heartRateVariabilitySDNN
    case restingHeartRate
    case activeEnergyBurned
    case sleepAnalysis
    case bodyMass
    case vo2Max
    case respiratoryRate
    case oxygenSaturation
    case appleSleepingWristTemperature
    case heartRate
    case stepCount
    case basalEnergyBurned
    case workout

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
        case .bodyMass:
            HKQuantityType(.bodyMass)
        case .vo2Max:
            HKQuantityType(.vo2Max)
        case .respiratoryRate:
            HKQuantityType(.respiratoryRate)
        case .oxygenSaturation:
            HKQuantityType(.oxygenSaturation)
        case .appleSleepingWristTemperature:
            HKQuantityType(.appleSleepingWristTemperature)
        case .heartRate:
            HKQuantityType(.heartRate)
        case .stepCount:
            HKQuantityType(.stepCount)
        case .basalEnergyBurned:
            HKQuantityType(.basalEnergyBurned)
        case .workout:
            HKWorkoutType.workoutType()
        }
    }

    var anchorTypeIdentifier: String {
        sampleType.identifier
    }

    var isWorkout: Bool {
        self == .workout
    }

    static var metricKinds: [HealthKitTier1Kind] {
        allCases.filter { !$0.isWorkout }
    }

    static var readObjectTypes: Set<HKObjectType> {
        Set(allCases.map(\.sampleType))
    }
}

enum HealthKitSyncLimits {
    static let lookbackDays = 120
}
