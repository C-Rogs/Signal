import Foundation

struct SleepInterval: Sendable, Equatable {
    let start: Date
    let end: Date
    let isLegacy: Bool

    var durationSeconds: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct LatestSample: Sendable, Equatable {
    let value: Double
    let sampleDate: Date
}

struct BloodPressurePair: Sendable, Equatable {
    let systolic: Double
    let diastolic: Double
    let sampleDate: Date
}

struct DayAccumulator: Sendable {
    var hrvSum: Double = 0
    var hrvCount: Int = 0
    var restingSum: Double = 0
    var restingCount: Int = 0
    var activeEnergyKcalSum: Double = 0
    var granularSleep: [SleepInterval] = []
    var legacySleep: [SleepInterval] = []
    var bodyMassLatest: LatestSample?
    var bodyFatLatest: LatestSample?
    var leanBodyMassLatest: LatestSample?
    var vo2MaxLatest: LatestSample?
    var respiratoryDuringSleep: [Double] = []
    var wristTempDuringSleep: [Double] = []
    var bloodOxygenDuringSleep: [Double] = []
    var sleepingBreathingDisturbancesDuringSleep: [Double] = []
    var heartRateSum: Double = 0
    var heartRateCount: Int = 0
    var heartRateMax: Double?
    var stepCountSum: Double = 0
    var basalEnergyKcalSum: Double = 0
    var walkingHeartRateSum: Double = 0
    var walkingHeartRateCount: Int = 0
    var appleExerciseMinutesSum: Double = 0
    var appleStandHourCount: Int = 0
    var physicalEffortActiveSum: Double = 0
    var physicalEffortActiveCount: Int = 0
    var timeInDaylightMinSum: Double = 0
    var bloodPressureLatest: BloodPressurePair?
}

struct NutritionDayAccumulator: Sendable {
    var dietaryEnergyKcalSum: Double = 0
    var proteinGSum: Double = 0
    var carbsGSum: Double = 0
    var fatTotalGSum: Double = 0
    var fatSaturatedGSum: Double = 0
    var fiberGSum: Double = 0
    var sugarGSum: Double = 0
    var sodiumMgSum: Double = 0
}

enum DailyMetricAggregator {
    static let importSource = "apple-health-export"
    static let healthKitLiveSource = "healthkit"

    static let physicalEffortActiveEpsilon = 0.0001

    static func overlaps(_ a: SleepInterval, _ b: SleepInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }

    static func sleepHours(for day: DayAccumulator) -> Double {
        let granularSeconds = day.granularSleep.reduce(0.0) { $0 + $1.durationSeconds }
        let legacySeconds = day.legacySleep.reduce(0.0) { partial, legacy in
            let overlapsGranular = day.granularSleep.contains { overlaps(legacy, $0) }
            if overlapsGranular {
                return partial
            }
            return partial + legacy.durationSeconds
        }
        return (granularSeconds + legacySeconds) / 3600.0
    }

    static func allSleepIntervals(for day: DayAccumulator) -> [SleepInterval] {
        day.granularSleep + day.legacySleep
    }

    static func isDuringSleep(_ timestamp: Date, in day: DayAccumulator) -> Bool {
        for interval in allSleepIntervals(for: day) {
            if interval.start <= timestamp, timestamp < interval.end {
                return true
            }
        }
        return false
    }

    static func meanHRV(_ day: DayAccumulator) -> Double? {
        guard day.hrvCount > 0 else { return nil }
        return day.hrvSum / Double(day.hrvCount)
    }

    static func meanRestingHR(_ day: DayAccumulator) -> Double? {
        guard day.restingCount > 0 else { return nil }
        return day.restingSum / Double(day.restingCount)
    }

    static func activeEnergyKcal(_ day: DayAccumulator) -> Double? {
        guard day.activeEnergyKcalSum > 0 else { return nil }
        return day.activeEnergyKcalSum
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func latestValue(_ latest: LatestSample?) -> Double? {
        latest?.value
    }

    static func heartRateAvg(_ day: DayAccumulator) -> Double? {
        guard day.heartRateCount > 0 else { return nil }
        return day.heartRateSum / Double(day.heartRateCount)
    }

    static func walkingHeartRateAvg(_ day: DayAccumulator) -> Double? {
        guard day.walkingHeartRateCount > 0 else { return nil }
        return day.walkingHeartRateSum / Double(day.walkingHeartRateCount)
    }

    static func physicalEffort(_ day: DayAccumulator) -> Double? {
        guard day.physicalEffortActiveCount > 0 else { return nil }
        return day.physicalEffortActiveSum / Double(day.physicalEffortActiveCount)
    }

    static func stepCount(_ day: DayAccumulator) -> Double? {
        guard day.stepCountSum > 0 else { return nil }
        return day.stepCountSum
    }

    static func basalEnergyKcal(_ day: DayAccumulator) -> Double? {
        guard day.basalEnergyKcalSum > 0 else { return nil }
        return day.basalEnergyKcalSum
    }

    static func appleExerciseMinutes(_ day: DayAccumulator) -> Double? {
        guard day.appleExerciseMinutesSum > 0 else { return nil }
        return day.appleExerciseMinutesSum
    }

    static func appleStandHours(_ day: DayAccumulator) -> Double? {
        guard day.appleStandHourCount > 0 else { return nil }
        return Double(day.appleStandHourCount)
    }

    static func timeInDaylightMin(_ day: DayAccumulator) -> Double? {
        guard day.timeInDaylightMinSum > 0 else { return nil }
        return day.timeInDaylightMinSum
    }

    static func sleepingBreathingDisturbances(_ day: DayAccumulator) -> Double? {
        guard !day.sleepingBreathingDisturbancesDuringSleep.isEmpty else { return nil }
        return day.sleepingBreathingDisturbancesDuringSleep.reduce(0, +)
    }

    static func normalizedBodyFatPercentage(value: Double, unit: String?) -> Double {
        let normalizedUnit = unit?.lowercased() ?? "%"
        if normalizedUnit == "%", value <= 1 {
            return value * 100
        }
        return value
    }

    static func toDailyMetric(
        wakeDay: Date,
        day: DayAccumulator,
        source: String = importSource
    ) -> DailyMetric? {
        let hrv = meanHRV(day)
        let resting = meanRestingHR(day)
        let energy = activeEnergyKcal(day)
        let sleep = sleepHours(for: day)
        let hasSleep = sleep > 0
        let bodyMass = latestValue(day.bodyMassLatest)
        let bodyFat = latestValue(day.bodyFatLatest)
        let leanMass = latestValue(day.leanBodyMassLatest)
        let vo2 = latestValue(day.vo2MaxLatest)
        let respiratory = mean(day.respiratoryDuringSleep)
        let wristTemp = mean(day.wristTempDuringSleep)
        let spo2 = mean(day.bloodOxygenDuringSleep)
        let breathingDisturbances = sleepingBreathingDisturbances(day)
        let hrMax = day.heartRateMax
        let hrAvg = heartRateAvg(day)
        let steps = stepCount(day)
        let basal = basalEnergyKcal(day)
        let walkingHR = walkingHeartRateAvg(day)
        let exerciseMin = appleExerciseMinutes(day)
        let standHours = appleStandHours(day)
        let effort = physicalEffort(day)
        let daylight = timeInDaylightMin(day)
        let systolic = day.bloodPressureLatest?.systolic
        let diastolic = day.bloodPressureLatest?.diastolic

        let hasAny = hrv != nil
            || resting != nil
            || energy != nil
            || hasSleep
            || bodyMass != nil
            || bodyFat != nil
            || leanMass != nil
            || vo2 != nil
            || respiratory != nil
            || wristTemp != nil
            || spo2 != nil
            || breathingDisturbances != nil
            || hrMax != nil
            || hrAvg != nil
            || steps != nil
            || basal != nil
            || walkingHR != nil
            || exerciseMin != nil
            || standHours != nil
            || effort != nil
            || daylight != nil
            || systolic != nil
            || diastolic != nil
        guard hasAny else { return nil }

        return DailyMetric(
            date: wakeDay,
            hrvSDNN_ms: hrv,
            restingHR: resting,
            activeEnergy_kcal: energy,
            sleepHours: hasSleep ? sleep : nil,
            bodyMassKg: bodyMass,
            vo2Max: vo2,
            respiratoryRate: respiratory,
            wristTemperatureDeltaC: wristTemp,
            bloodOxygenPct: spo2,
            heartRateMax: hrMax,
            heartRateAvg: hrAvg,
            stepCount: steps,
            basalEnergyKcal: basal,
            bodyFatPercentage: bodyFat,
            leanBodyMassKg: leanMass,
            walkingHeartRateAvg: walkingHR,
            appleExerciseMinutes: exerciseMin,
            appleStandHours: standHours,
            physicalEffort: effort,
            timeInDaylightMin: daylight,
            sleepingBreathingDisturbances: breathingDisturbances,
            bloodPressureSystolic: systolic,
            bloodPressureDiastolic: diastolic,
            source: source
        )
    }

    static func toDailyNutrition(
        day: Date,
        accumulator: NutritionDayAccumulator,
        source: String = importSource
    ) -> DailyNutrition? {
        let hasAny = accumulator.dietaryEnergyKcalSum > 0
            || accumulator.proteinGSum > 0
            || accumulator.carbsGSum > 0
            || accumulator.fatTotalGSum > 0
            || accumulator.fatSaturatedGSum > 0
            || accumulator.fiberGSum > 0
            || accumulator.sugarGSum > 0
            || accumulator.sodiumMgSum > 0
        guard hasAny else { return nil }

        return DailyNutrition(
            date: day,
            dietaryEnergyKcal: accumulator.dietaryEnergyKcalSum > 0 ? accumulator.dietaryEnergyKcalSum : nil,
            proteinG: accumulator.proteinGSum > 0 ? accumulator.proteinGSum : nil,
            carbsG: accumulator.carbsGSum > 0 ? accumulator.carbsGSum : nil,
            fatTotalG: accumulator.fatTotalGSum > 0 ? accumulator.fatTotalGSum : nil,
            fatSaturatedG: accumulator.fatSaturatedGSum > 0 ? accumulator.fatSaturatedGSum : nil,
            fiberG: accumulator.fiberGSum > 0 ? accumulator.fiberGSum : nil,
            sugarG: accumulator.sugarGSum > 0 ? accumulator.sugarGSum : nil,
            sodiumMg: accumulator.sodiumMgSum > 0 ? accumulator.sodiumMgSum : nil,
            source: source
        )
    }
}

final class DailyMetricAggregationState: @unchecked Sendable {
    private enum PendingSleepMetricKind {
        case respiratory
        case wristTemperature
        case bloodOxygen
        case sleepingBreathingDisturbances
    }

    private struct PendingSleepMetric: Sendable {
        let kind: PendingSleepMetricKind
        let sampleDate: Date
        let value: Double
    }

    let calendar: Calendar
    private var quantityDays: [Date: DayAccumulator] = [:]
    private var sleepByWakeDay: [Date: DayAccumulator] = [:]
    private var pendingSleepMetrics: [PendingSleepMetric] = []

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func quantityBucket(for day: Date) -> DayAccumulator {
        quantityDays[day] ?? DayAccumulator()
    }

    private func setQuantityBucket(_ bucket: DayAccumulator, for day: Date) {
        quantityDays[day] = bucket
    }

    private func sleepBucket(for wakeDay: Date) -> DayAccumulator {
        sleepByWakeDay[wakeDay] ?? DayAccumulator()
    }

    private func setSleepBucket(_ bucket: DayAccumulator, for wakeDay: Date) {
        sleepByWakeDay[wakeDay] = bucket
    }

    private func wakeDayContainingSleepSample(at timestamp: Date) -> Date? {
        for (wakeDay, bucket) in sleepByWakeDay {
            if DailyMetricAggregator.isDuringSleep(timestamp, in: bucket) {
                return wakeDay
            }
        }
        return nil
    }

    private func applyLatest(
        value: Double,
        sampleDate: Date,
        into latest: inout LatestSample?
    ) {
        if let existing = latest {
            if sampleDate >= existing.sampleDate {
                latest = LatestSample(value: value, sampleDate: sampleDate)
            }
        } else {
            latest = LatestSample(value: value, sampleDate: sampleDate)
        }
    }

    private func applyLatestBloodPressure(systolic: Double, diastolic: Double, sampleDate: Date, into bucket: inout DayAccumulator) {
        if let existing = bucket.bloodPressureLatest {
            if sampleDate >= existing.sampleDate {
                bucket.bloodPressureLatest = BloodPressurePair(
                    systolic: systolic,
                    diastolic: diastolic,
                    sampleDate: sampleDate
                )
            }
        } else {
            bucket.bloodPressureLatest = BloodPressurePair(
                systolic: systolic,
                diastolic: diastolic,
                sampleDate: sampleDate
            )
        }
    }

    private func attributeSleepMetric(
        kind: PendingSleepMetricKind,
        value: Double,
        sampleDate: Date
    ) {
        if let wakeDay = wakeDayContainingSleepSample(at: sampleDate) {
            var bucket = quantityBucket(for: wakeDay)
            appendSleepMetric(kind: kind, value: value, to: &bucket)
            setQuantityBucket(bucket, for: wakeDay)
        } else {
            pendingSleepMetrics.append(PendingSleepMetric(kind: kind, sampleDate: sampleDate, value: value))
        }
    }

    private func appendSleepMetric(kind: PendingSleepMetricKind, value: Double, to bucket: inout DayAccumulator) {
        switch kind {
        case .respiratory:
            bucket.respiratoryDuringSleep.append(value)
        case .wristTemperature:
            bucket.wristTempDuringSleep.append(value)
        case .bloodOxygen:
            bucket.bloodOxygenDuringSleep.append(value)
        case .sleepingBreathingDisturbances:
            bucket.sleepingBreathingDisturbancesDuringSleep.append(value)
        }
    }

    private func resolvePendingSleepMetrics() {
        guard !pendingSleepMetrics.isEmpty else { return }
        for item in pendingSleepMetrics {
            let targetDay: Date
            if let wakeDay = wakeDayContainingSleepSample(at: item.sampleDate) {
                targetDay = wakeDay
            } else {
                targetDay = startOfDay(for: item.sampleDate)
            }
            var bucket = quantityBucket(for: targetDay)
            appendSleepMetric(kind: item.kind, value: item.value, to: &bucket)
            setQuantityBucket(bucket, for: targetDay)
        }
        pendingSleepMetrics.removeAll(keepingCapacity: false)
    }

    func addHRV(value: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.hrvSum += value
        bucket.hrvCount += 1
        setQuantityBucket(bucket, for: day)
    }

    func addRestingHR(value: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.restingSum += value
        bucket.restingCount += 1
        setQuantityBucket(bucket, for: day)
    }

    func addActiveEnergy(kcal: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.activeEnergyKcalSum += kcal
        setQuantityBucket(bucket, for: day)
    }

    func addBodyMass(kg: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatest(value: kg, sampleDate: sampleDate, into: &bucket.bodyMassLatest)
        setQuantityBucket(bucket, for: day)
    }

    func addBodyFatPercentage(pct: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatest(value: pct, sampleDate: sampleDate, into: &bucket.bodyFatLatest)
        setQuantityBucket(bucket, for: day)
    }

    func addLeanBodyMass(kg: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatest(value: kg, sampleDate: sampleDate, into: &bucket.leanBodyMassLatest)
        setQuantityBucket(bucket, for: day)
    }

    func addVO2Max(value: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatest(value: value, sampleDate: sampleDate, into: &bucket.vo2MaxLatest)
        setQuantityBucket(bucket, for: day)
    }

    func addRespiratoryRate(brpm: Double, sampleDate: Date) {
        attributeSleepMetric(kind: .respiratory, value: brpm, sampleDate: sampleDate)
    }

    func addWristTemperatureDeltaC(delta: Double, sampleDate: Date) {
        attributeSleepMetric(kind: .wristTemperature, value: delta, sampleDate: sampleDate)
    }

    func addBloodOxygenPct(pct: Double, sampleDate: Date) {
        attributeSleepMetric(kind: .bloodOxygen, value: pct, sampleDate: sampleDate)
    }

    func addSleepingBreathingDisturbances(count: Double, sampleDate: Date) {
        attributeSleepMetric(kind: .sleepingBreathingDisturbances, value: count, sampleDate: sampleDate)
    }

    func addHeartRate(bpm: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        bucket.heartRateSum += bpm
        bucket.heartRateCount += 1
        if let currentMax = bucket.heartRateMax {
            bucket.heartRateMax = max(currentMax, bpm)
        } else {
            bucket.heartRateMax = bpm
        }
        setQuantityBucket(bucket, for: day)
    }

    func addWalkingHeartRate(bpm: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.walkingHeartRateSum += bpm
        bucket.walkingHeartRateCount += 1
        setQuantityBucket(bucket, for: day)
    }

    func addStepCount(count: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.stepCountSum += count
        setQuantityBucket(bucket, for: day)
    }

    func addBasalEnergy(kcal: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.basalEnergyKcalSum += kcal
        setQuantityBucket(bucket, for: day)
    }

    func addAppleExerciseTime(minutes: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.appleExerciseMinutesSum += minutes
        setQuantityBucket(bucket, for: day)
    }

    func addAppleStandHour(stood: Bool, startDate: Date) {
        guard stood else { return }
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.appleStandHourCount += 1
        setQuantityBucket(bucket, for: day)
    }

    func addPhysicalEffort(value: Double, startDate: Date) {
        guard value > DailyMetricAggregator.physicalEffortActiveEpsilon else { return }
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.physicalEffortActiveSum += value
        bucket.physicalEffortActiveCount += 1
        setQuantityBucket(bucket, for: day)
    }

    func addTimeInDaylight(minutes: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityBucket(for: day)
        bucket.timeInDaylightMinSum += minutes
        setQuantityBucket(bucket, for: day)
    }

    func addBloodPressure(systolic: Double, diastolic: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatestBloodPressure(systolic: systolic, diastolic: diastolic, sampleDate: sampleDate, into: &bucket)
        setQuantityBucket(bucket, for: day)
    }

    func addSleepInterval(start: Date, end: Date, isLegacy: Bool) {
        let wakeDay = startOfDay(for: end)
        var bucket = sleepByWakeDay[wakeDay] ?? DayAccumulator()
        let interval = SleepInterval(start: start, end: end, isLegacy: isLegacy)
        if isLegacy {
            bucket.legacySleep.append(interval)
        } else {
            bucket.granularSleep.append(interval)
        }
        sleepByWakeDay[wakeDay] = bucket
    }

    func allDayStarts() -> [Date] {
        resolvePendingSleepMetrics()
        return Set(quantityDays.keys).union(sleepByWakeDay.keys).sorted()
    }

    func mergedMetric(for dayStart: Date) -> DailyMetric? {
        mergedMetric(for: dayStart, source: DailyMetricAggregator.importSource)
    }

    func mergedMetric(for dayStart: Date, source: String) -> DailyMetric? {
        resolvePendingSleepMetrics()
        var combined = quantityDays[dayStart] ?? DayAccumulator()
        if let sleep = sleepByWakeDay[dayStart] {
            combined.granularSleep = sleep.granularSleep
            combined.legacySleep = sleep.legacySleep
        }
        return DailyMetricAggregator.toDailyMetric(wakeDay: dayStart, day: combined, source: source)
    }

    var dayCount: Int {
        allDayStarts().count
    }

    func releaseParsedData() {
        quantityDays.removeAll(keepingCapacity: false)
        sleepByWakeDay.removeAll(keepingCapacity: false)
        pendingSleepMetrics.removeAll(keepingCapacity: false)
    }
}

final class DailyNutritionAggregationState: @unchecked Sendable {
    let calendar: Calendar
    private var days: [Date: NutritionDayAccumulator] = [:]

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func bucket(for day: Date) -> NutritionDayAccumulator {
        days[day] ?? NutritionDayAccumulator()
    }

    private func setBucket(_ bucket: NutritionDayAccumulator, for day: Date) {
        days[day] = bucket
    }

    func addDietaryEnergy(kcal: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.dietaryEnergyKcalSum += kcal
        setBucket(b, for: day)
    }

    func addProtein(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.proteinGSum += g
        setBucket(b, for: day)
    }

    func addCarbs(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.carbsGSum += g
        setBucket(b, for: day)
    }

    func addFatTotal(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.fatTotalGSum += g
        setBucket(b, for: day)
    }

    func addFatSaturated(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.fatSaturatedGSum += g
        setBucket(b, for: day)
    }

    func addFiber(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.fiberGSum += g
        setBucket(b, for: day)
    }

    func addSugar(g: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.sugarGSum += g
        setBucket(b, for: day)
    }

    func addSodium(mg: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var b = bucket(for: day)
        b.sodiumMgSum += mg
        setBucket(b, for: day)
    }

    func allDayStarts() -> [Date] {
        days.keys.sorted()
    }

    func mergedNutrition(for dayStart: Date) -> DailyNutrition? {
        mergedNutrition(for: dayStart, source: DailyMetricAggregator.importSource)
    }

    func mergedNutrition(for dayStart: Date, source: String) -> DailyNutrition? {
        guard let accumulator = days[dayStart] else { return nil }
        return DailyMetricAggregator.toDailyNutrition(day: dayStart, accumulator: accumulator, source: source)
    }

    func releaseParsedData() {
        days.removeAll(keepingCapacity: false)
    }
}

enum ImportDayUnion {
    static func unionDayStarts(
        metricDays: [Date],
        nutritionDays: [Date],
        workoutDays: [Date]
    ) -> [Date] {
        Set(metricDays).union(nutritionDays).union(workoutDays).sorted()
    }

    static func workoutDayStarts(from workouts: [AppleWorkout], calendar: Calendar) -> [Date] {
        Set(workouts.map { calendar.startOfDay(for: $0.startDate) }).sorted()
    }
}
