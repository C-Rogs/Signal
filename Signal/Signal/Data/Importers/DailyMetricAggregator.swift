import Foundation

struct SleepInterval: Sendable, Equatable {
    let start: Date
    let end: Date
    let isLegacy: Bool

    var durationSeconds: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct DayAccumulator: Sendable {
    var hrvSum: Double = 0
    var hrvCount: Int = 0
    var restingSum: Double = 0
    var restingCount: Int = 0
    var activeEnergyKcalSum: Double = 0
    var granularSleep: [SleepInterval] = []
    var legacySleep: [SleepInterval] = []
}

enum DailyMetricAggregator {
    static let importSource = "apple-health-export"

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

    static func toDailyMetric(wakeDay: Date, day: DayAccumulator) -> DailyMetric? {
        let hrv = meanHRV(day)
        let resting = meanRestingHR(day)
        let energy = activeEnergyKcal(day)
        let sleep = sleepHours(for: day)
        let hasSleep = sleep > 0
        let hasAny = hrv != nil || resting != nil || energy != nil || hasSleep
        guard hasAny else { return nil }

        return DailyMetric(
            date: wakeDay,
            hrvSDNN_ms: hrv,
            restingHR: resting,
            activeEnergy_kcal: energy,
            sleepHours: hasSleep ? sleep : nil,
            source: importSource
        )
    }
}

final class DailyMetricAggregationState: @unchecked Sendable {
    let calendar: Calendar
    private var quantityDays: [Date: DayAccumulator] = [:]
    private var sleepByWakeDay: [Date: DayAccumulator] = [:]

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func addHRV(value: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityDays[day] ?? DayAccumulator()
        bucket.hrvSum += value
        bucket.hrvCount += 1
        quantityDays[day] = bucket
    }

    func addRestingHR(value: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityDays[day] ?? DayAccumulator()
        bucket.restingSum += value
        bucket.restingCount += 1
        quantityDays[day] = bucket
    }

    func addActiveEnergy(kcal: Double, startDate: Date) {
        let day = startOfDay(for: startDate)
        var bucket = quantityDays[day] ?? DayAccumulator()
        bucket.activeEnergyKcalSum += kcal
        quantityDays[day] = bucket
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
        Set(quantityDays.keys).union(sleepByWakeDay.keys).sorted()
    }

    func mergedMetric(for dayStart: Date) -> DailyMetric? {
        var combined = quantityDays[dayStart] ?? DayAccumulator()
        if let sleep = sleepByWakeDay[dayStart] {
            combined.granularSleep = sleep.granularSleep
            combined.legacySleep = sleep.legacySleep
        }
        return DailyMetricAggregator.toDailyMetric(wakeDay: dayStart, day: combined)
    }

    var dayCount: Int {
        allDayStarts().count
    }
}
