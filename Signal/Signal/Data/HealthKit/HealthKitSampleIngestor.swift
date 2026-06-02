import Foundation
import HealthKit

enum HealthKitSampleIngestor {
    static func affectedWakeDay(for sample: HKSample, calendar: Calendar) -> Date {
        switch sample {
        case let category as HKCategorySample where category.categoryType == HKCategoryType(.sleepAnalysis):
            calendar.startOfDay(for: category.endDate)
        case let workout as HKWorkout:
            calendar.startOfDay(for: workout.startDate)
        default:
            calendar.startOfDay(for: sample.startDate)
        }
    }

    static func ingest(_ sample: HKSample, into aggregation: DailyMetricAggregationState) {
        if let workout = sample as? HKWorkout {
            _ = workout
            return
        }
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
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            guard let value = normalizedBodyMassKg(from: sample.quantity) else { return }
            aggregation.addBodyMass(kg: value, sampleDate: sample.endDate)
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            guard let value = normalizedVO2Max(from: sample.quantity) else { return }
            aggregation.addVO2Max(value: value, sampleDate: sample.endDate)
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            guard let value = normalizedRespiratoryRate(from: sample.quantity) else { return }
            aggregation.addRespiratoryRate(brpm: value, sampleDate: sample.startDate)
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            guard let value = normalizedBloodOxygenPct(from: sample.quantity) else { return }
            aggregation.addBloodOxygenPct(pct: value, sampleDate: sample.startDate)
        case HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue:
            guard let value = normalizedWristTemperatureDeltaC(from: sample.quantity) else { return }
            aggregation.addWristTemperatureDeltaC(delta: value, sampleDate: sample.startDate)
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            guard let value = normalizedHeartRate(from: sample.quantity) else { return }
            aggregation.addHeartRate(bpm: value, sampleDate: sample.startDate)
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            guard let value = normalizedStepCount(from: sample.quantity) else { return }
            aggregation.addStepCount(count: value, startDate: sample.startDate)
        case HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            guard let value = normalizedActiveEnergyKcal(from: sample.quantity) else { return }
            aggregation.addBasalEnergy(kcal: value, startDate: sample.startDate)
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

    static func normalizedHeartRate(from quantity: HKQuantity) -> Double? {
        normalizedRestingHR(from: quantity)
    }

    static func normalizedActiveEnergyKcal(from quantity: HKQuantity) -> Double? {
        let kcal = HKUnit.kilocalorie()
        let value = quantity.doubleValue(for: kcal)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedBodyMassKg(from quantity: HKQuantity) -> Double? {
        let kg = HKUnit.gramUnit(with: .kilo)
        let value = quantity.doubleValue(for: kg)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedVO2Max(from quantity: HKQuantity) -> Double? {
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo))
            .unitDivided(by: .minute())
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedRespiratoryRate(from quantity: HKQuantity) -> Double? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    static func normalizedBloodOxygenPct(from quantity: HKQuantity) -> Double? {
        let fraction = HKUnit.percent()
        let value = quantity.doubleValue(for: fraction)
        guard value.isFinite, value > 0 else { return nil }
        if value <= 1 {
            return value * 100
        }
        return value
    }

    static func normalizedWristTemperatureDeltaC(from quantity: HKQuantity) -> Double? {
        let celsius = HKUnit.degreeCelsius()
        let value = quantity.doubleValue(for: celsius)
        guard value.isFinite else { return nil }
        return value
    }

    static func normalizedStepCount(from quantity: HKQuantity) -> Double? {
        let count = HKUnit.count()
        let value = quantity.doubleValue(for: count)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }
}

struct SyntheticHealthQuantitySample: Sendable {
    let quantityTypeIdentifier: HKQuantityTypeIdentifier
    let value: Double
    let unit: HKUnit
    let startDate: Date
    let endDate: Date?

    init(
        quantityTypeIdentifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        startDate: Date,
        endDate: Date? = nil
    ) {
        self.quantityTypeIdentifier = quantityTypeIdentifier
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
    }
}

struct SyntheticHealthSleepSample: Sendable {
    let sleepValue: Int
    let startDate: Date
    let endDate: Date
}

enum SyntheticHealthKitSampleIngestor {
    static func ingest(_ sample: SyntheticHealthQuantitySample, into aggregation: DailyMetricAggregationState) {
        let quantity = HKQuantity(unit: sample.unit, doubleValue: sample.value)
        let sampleDate = sample.endDate ?? sample.startDate
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
        case .bodyMass:
            guard let value = HealthKitSampleIngestor.normalizedBodyMassKg(from: quantity) else { return }
            aggregation.addBodyMass(kg: value, sampleDate: sampleDate)
        case .vo2Max:
            guard let value = HealthKitSampleIngestor.normalizedVO2Max(from: quantity) else { return }
            aggregation.addVO2Max(value: value, sampleDate: sampleDate)
        case .respiratoryRate:
            guard let value = HealthKitSampleIngestor.normalizedRespiratoryRate(from: quantity) else { return }
            aggregation.addRespiratoryRate(brpm: value, sampleDate: sample.startDate)
        case .oxygenSaturation:
            guard let value = HealthKitSampleIngestor.normalizedBloodOxygenPct(from: quantity) else { return }
            aggregation.addBloodOxygenPct(pct: value, sampleDate: sample.startDate)
        case .appleSleepingWristTemperature:
            guard let value = HealthKitSampleIngestor.normalizedWristTemperatureDeltaC(from: quantity) else { return }
            aggregation.addWristTemperatureDeltaC(delta: value, sampleDate: sample.startDate)
        case .heartRate:
            guard let value = HealthKitSampleIngestor.normalizedHeartRate(from: quantity) else { return }
            aggregation.addHeartRate(bpm: value, sampleDate: sample.startDate)
        case .stepCount:
            guard let value = HealthKitSampleIngestor.normalizedStepCount(from: quantity) else { return }
            aggregation.addStepCount(count: value, startDate: sample.startDate)
        case .basalEnergyBurned:
            guard let value = HealthKitSampleIngestor.normalizedActiveEnergyKcal(from: quantity) else { return }
            aggregation.addBasalEnergy(kcal: value, startDate: sample.startDate)
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
