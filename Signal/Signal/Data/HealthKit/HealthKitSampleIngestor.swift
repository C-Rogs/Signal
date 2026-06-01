import Foundation
import HealthKit

enum HealthKitSampleIngestor {
    static func affectedWakeDay(for sample: HKSample, calendar: Calendar) -> Date {
        switch sample {
        case let category as HKCategorySample where category.categoryType == HKCategoryType(.sleepAnalysis):
            calendar.startOfDay(for: category.endDate)
        default:
            calendar.startOfDay(for: sample.startDate)
        }
    }

    static func ingest(_ sample: HKSample, into aggregation: DailyMetricAggregationState) {
        switch sample {
        case let quantity as HKQuantitySample:
            ingestQuantity(quantity, into: aggregation)
        case let category as HKCategorySample:
            ingestSleep(category, into: aggregation)
        default:
            break
        }
    }

    static func ingestQuantity(_ sample: HKQuantitySample, into aggregation: DailyMetricAggregationState) {
        let identifier = sample.quantityType.identifier
        switch identifier {
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            guard let value = normalizedHRV(from: sample.quantity) else { return }
            aggregation.addHRV(value: value, startDate: sample.startDate)
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            guard let value = normalizedRestingHR(from: sample.quantity) else { return }
            aggregation.addRestingHR(value: value, startDate: sample.startDate)
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            guard let value = normalizedActiveEnergyKcal(from: sample.quantity) else { return }
            aggregation.addActiveEnergy(kcal: value, startDate: sample.startDate)
        default:
            break
        }
    }

    static func ingestSleep(_ sample: HKCategorySample, into aggregation: DailyMetricAggregationState) {
        guard let asleep = sleepAsleepKind(for: sample.value) else { return }
        aggregation.addSleepInterval(
            start: sample.startDate,
            end: sample.endDate,
            isLegacy: asleep == .legacy
        )
    }

    private enum SleepAsleepKind {
        case legacy
        case granular
    }

    private static let legacyAsleepRawValue = 1

    private static func sleepAsleepKind(for rawValue: Int) -> SleepAsleepKind? {
        if rawValue == legacyAsleepRawValue {
            return .legacy
        }
        let granularValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        if granularValues.contains(rawValue) {
            return .granular
        }
        return nil
    }

    static func normalizedHRV(from quantity: HKQuantity) -> Double? {
        let ms = HKUnit.secondUnit(with: .milli)
        let value = quantity.doubleValue(for: ms)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedRestingHR(from quantity: HKQuantity) -> Double? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedActiveEnergyKcal(from quantity: HKQuantity) -> Double? {
        let kcal = HKUnit.kilocalorie()
        let value = quantity.doubleValue(for: kcal)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }
}

struct SyntheticHealthQuantitySample: Sendable {
    let quantityTypeIdentifier: HKQuantityTypeIdentifier
    let value: Double
    let unit: HKUnit
    let startDate: Date
}

struct SyntheticHealthSleepSample: Sendable {
    let sleepValue: Int
    let startDate: Date
    let endDate: Date
}

enum SyntheticHealthKitSampleIngestor {
    static func ingest(_ sample: SyntheticHealthQuantitySample, into aggregation: DailyMetricAggregationState) {
        let quantity = HKQuantity(unit: sample.unit, doubleValue: sample.value)
        switch sample.quantityTypeIdentifier {
        case .heartRateVariabilitySDNN:
            guard let value = HealthKitSampleIngestor.normalizedHRV(from: quantity) else { return }
            aggregation.addHRV(value: value, startDate: sample.startDate)
        case .restingHeartRate:
            guard let value = HealthKitSampleIngestor.normalizedRestingHR(from: quantity) else { return }
            aggregation.addRestingHR(value: value, startDate: sample.startDate)
        case .activeEnergyBurned:
            guard let value = HealthKitSampleIngestor.normalizedActiveEnergyKcal(from: quantity) else { return }
            aggregation.addActiveEnergy(kcal: value, startDate: sample.startDate)
        default:
            break
        }
    }

    static func ingest(_ sample: SyntheticHealthSleepSample, into aggregation: DailyMetricAggregationState) {
        guard let asleep = sleepAsleepKind(for: sample.sleepValue) else { return }
        aggregation.addSleepInterval(
            start: sample.startDate,
            end: sample.endDate,
            isLegacy: asleep == .legacy
        )
    }

    private enum SleepAsleepKind {
        case legacy
        case granular
    }

    private static let legacyAsleepRawValue = 1

    private static func sleepAsleepKind(for rawValue: Int) -> SleepAsleepKind? {
        if rawValue == legacyAsleepRawValue {
            return .legacy
        }
        let granularValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        if granularValues.contains(rawValue) {
            return .granular
        }
        return nil
    }
}
