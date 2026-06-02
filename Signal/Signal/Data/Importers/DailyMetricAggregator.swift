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

struct DayAccumulator: Sendable {
    var hrvSum: Double = 0
    var hrvCount: Int = 0
    var restingSum: Double = 0
    var restingCount: Int = 0
    var activeEnergyKcalSum: Double = 0
    var granularSleep: [SleepInterval] = []
    var legacySleep: [SleepInterval] = []
    var bodyMassLatest: LatestSample?
    var vo2MaxLatest: LatestSample?
    var respiratoryDuringSleep: [Double] = []
    var wristTempDuringSleep: [Double] = []
    var bloodOxygenDuringSleep: [Double] = []
    var heartRateSum: Double = 0
    var heartRateCount: Int = 0
    var heartRateMax: Double?
    var stepCountSum: Double = 0
    var basalEnergyKcalSum: Double = 0
}

enum DailyMetricAggregator {
    static let importSource = "apple-health-export"
    static let healthKitLiveSource = "healthkit"

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

    static func stepCount(_ day: DayAccumulator) -> Double? {
        guard day.stepCountSum > 0 else { return nil }
        return day.stepCountSum
    }

    static func basalEnergyKcal(_ day: DayAccumulator) -> Double? {
        guard day.basalEnergyKcalSum > 0 else { return nil }
        return day.basalEnergyKcalSum
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
        let vo2 = latestValue(day.vo2MaxLatest)
        let respiratory = mean(day.respiratoryDuringSleep)
        let wristTemp = mean(day.wristTempDuringSleep)
        let spo2 = mean(day.bloodOxygenDuringSleep)
        let hrMax = day.heartRateMax
        let hrAvg = heartRateAvg(day)
        let steps = stepCount(day)
        let basal = basalEnergyKcal(day)

        let hasAny = hrv != nil
            || resting != nil
            || energy != nil
            || hasSleep
            || bodyMass != nil
            || vo2 != nil
            || respiratory != nil
            || wristTemp != nil
            || spo2 != nil
            || hrMax != nil
            || hrAvg != nil
            || steps != nil
            || basal != nil
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
            source: source
        )
    }
}

final class DailyMetricAggregationState: @unchecked Sendable {
    private enum PendingSleepMetricKind {
        case respiratory
        case wristTemperature
        case bloodOxygen
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

    private func mergedSleepIntervals(for wakeDay: Date) -> [SleepInterval] {
        guard let sleep = sleepByWakeDay[wakeDay] else { return [] }
        return DailyMetricAggregator.allSleepIntervals(for: sleep)
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

    private func resolvePendingSleepMetrics() {
        guard !pendingSleepMetrics.isEmpty else { return }
        var unresolved: [PendingSleepMetric] = []
        unresolved.reserveCapacity(pendingSleepMetrics.count)
        for item in pendingSleepMetrics {
            guard let wakeDay = wakeDayContainingSleepSample(at: item.sampleDate) else {
                unresolved.append(item)
                continue
            }
            var bucket = quantityBucket(for: wakeDay)
            switch item.kind {
            case .respiratory:
                bucket.respiratoryDuringSleep.append(item.value)
            case .wristTemperature:
                bucket.wristTempDuringSleep.append(item.value)
            case .bloodOxygen:
                bucket.bloodOxygenDuringSleep.append(item.value)
            }
            setQuantityBucket(bucket, for: wakeDay)
        }
        pendingSleepMetrics = unresolved
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

    func addVO2Max(value: Double, sampleDate: Date) {
        let day = startOfDay(for: sampleDate)
        var bucket = quantityBucket(for: day)
        applyLatest(value: value, sampleDate: sampleDate, into: &bucket.vo2MaxLatest)
        setQuantityBucket(bucket, for: day)
    }

    func addRespiratoryRate(brpm: Double, sampleDate: Date) {
        if let wakeDay = wakeDayContainingSleepSample(at: sampleDate) {
            var bucket = quantityBucket(for: wakeDay)
            bucket.respiratoryDuringSleep.append(brpm)
            setQuantityBucket(bucket, for: wakeDay)
        } else {
            pendingSleepMetrics.append(PendingSleepMetric(kind: .respiratory, sampleDate: sampleDate, value: brpm))
        }
    }

    func addWristTemperatureDeltaC(delta: Double, sampleDate: Date) {
        if let wakeDay = wakeDayContainingSleepSample(at: sampleDate) {
            var bucket = quantityBucket(for: wakeDay)
            bucket.wristTempDuringSleep.append(delta)
            setQuantityBucket(bucket, for: wakeDay)
        } else {
            pendingSleepMetrics.append(
                PendingSleepMetric(kind: .wristTemperature, sampleDate: sampleDate, value: delta)
            )
        }
    }

    func addBloodOxygenPct(pct: Double, sampleDate: Date) {
        if let wakeDay = wakeDayContainingSleepSample(at: sampleDate) {
            var bucket = quantityBucket(for: wakeDay)
            bucket.bloodOxygenDuringSleep.append(pct)
            setQuantityBucket(bucket, for: wakeDay)
        } else {
            pendingSleepMetrics.append(PendingSleepMetric(kind: .bloodOxygen, sampleDate: sampleDate, value: pct))
        }
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
