import Foundation
import HealthKit

enum HealthKitTier1Kind: String, CaseIterable, Sendable {
    case heartRateVariabilitySDNN
    case restingHeartRate
    case activeEnergyBurned
    case sleepAnalysis
    case bodyMass
    case bodyFatPercentage
    case leanBodyMass
    case vo2Max
    case respiratoryRate
    case oxygenSaturation
    case appleSleepingWristTemperature
    case heartRate
    case walkingHeartRateAverage
    case stepCount
    case basalEnergyBurned
    case appleExerciseTime
    case physicalEffort
    case timeInDaylight
    case appleSleepingBreathingDisturbances
    case appleStandHour
    case bloodPressure
    case dietaryEnergyConsumed
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFatTotal
    case dietaryFatSaturated
    case dietaryFiber
    case dietarySugar
    case dietarySodium
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
        case .bodyFatPercentage:
            HKQuantityType(.bodyFatPercentage)
        case .leanBodyMass:
            HKQuantityType(.leanBodyMass)
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
        case .walkingHeartRateAverage:
            HKQuantityType(.walkingHeartRateAverage)
        case .stepCount:
            HKQuantityType(.stepCount)
        case .basalEnergyBurned:
            HKQuantityType(.basalEnergyBurned)
        case .appleExerciseTime:
            HKQuantityType(.appleExerciseTime)
        case .physicalEffort:
            HKQuantityType(.physicalEffort)
        case .timeInDaylight:
            HKQuantityType(.timeInDaylight)
        case .appleSleepingBreathingDisturbances:
            HKQuantityType(.appleSleepingBreathingDisturbances)
        case .appleStandHour:
            HKCategoryType(.appleStandHour)
        case .bloodPressure:
            HKCorrelationType(.bloodPressure)
        case .dietaryEnergyConsumed:
            HKQuantityType(.dietaryEnergyConsumed)
        case .dietaryProtein:
            HKQuantityType(.dietaryProtein)
        case .dietaryCarbohydrates:
            HKQuantityType(.dietaryCarbohydrates)
        case .dietaryFatTotal:
            HKQuantityType(.dietaryFatTotal)
        case .dietaryFatSaturated:
            HKQuantityType(.dietaryFatSaturated)
        case .dietaryFiber:
            HKQuantityType(.dietaryFiber)
        case .dietarySugar:
            HKQuantityType(.dietarySugar)
        case .dietarySodium:
            HKQuantityType(.dietarySodium)
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

    var isBloodPressure: Bool {
        self == .bloodPressure
    }

    var isNutrition: Bool {
        Self.nutritionKinds.contains(self)
    }

    static var nutritionKinds: [HealthKitTier1Kind] {
        [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFatSaturated,
            .dietaryFiber,
            .dietarySugar,
            .dietarySodium,
        ]
    }

    static var metricKinds: [HealthKitTier1Kind] {
        allCases.filter { !$0.isWorkout && !$0.isNutrition && !$0.isBloodPressure }
    }

    static var anchoredSyncKinds: [HealthKitTier1Kind] {
        metricKinds + nutritionKinds + [.bloodPressure, .workout]
    }

    static var readObjectTypes: Set<HKObjectType> {
        Set(allCases.map(\.sampleType))
    }

    /// Types passed to `requestAuthorization` / `getRequestStatusForAuthorization`.
    /// Blood pressure correlations are read via component quantity types, not `HKCorrelationType`.
    static var authorizationReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for kind in allCases {
            if kind.isBloodPressure {
                types.insert(HKQuantityType(.bloodPressureSystolic))
                types.insert(HKQuantityType(.bloodPressureDiastolic))
            } else {
                types.insert(kind.sampleType)
            }
        }
        return types
    }
}

enum HealthKitSyncLimits {
    static let lookbackDays = 120
}
