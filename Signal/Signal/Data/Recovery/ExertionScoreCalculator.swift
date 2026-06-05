import Foundation
import os

enum ExertionScoreSource: String, Sendable, Equatable {
    case heartRate
    case rpe
    case blended
}

struct ExertionScore: Sendable, Equatable {
    let value: Double
    let hrComponent: Double?
    let volumeComponent: Double?
    let source: ExertionScoreSource
    let confidence: Double
    let isCalibrated: Bool
}

struct ExertionBaselines: Sendable, Equatable {
    let hrMax30d: Double
    let rhr60d: Double?
    let chronicSetMean28d: Double?
    let isCalibrated: Bool
}

struct WorkoutDaySession: Sendable, Equatable {
    let date: Date
    let workingSetCount: Int
    let meanRPE: Double?
    let hkEffortScore: Double?
}

enum ExertionScoreCalculator {
    static func baselines(
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        referenceDay: Date,
        calendar: Calendar
    ) -> ExertionBaselines {
        let end = calendar.startOfDay(for: referenceDay)
        let hrMax = hrMax30d(metrics: metrics, referenceDay: end, calendar: calendar)
        let rhr = rhr60d(metrics: metrics, referenceDay: end, calendar: calendar)
        let chronicMean = chronicSetMean28d(sessions: sessions, referenceDay: end, calendar: calendar)
        let calibrated = isCalibrated(metrics: metrics, sessions: sessions, referenceDay: end, calendar: calendar)

        return ExertionBaselines(
            hrMax30d: hrMax,
            rhr60d: rhr,
            chronicSetMean28d: chronicMean,
            isCalibrated: calibrated
        )
    }

    static func score(
        for day: Date,
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        baselines: ExertionBaselines,
        calendar: Calendar
    ) -> ExertionScore? {
        let targetDay = calendar.startOfDay(for: day)
        let daySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: targetDay) }
        let finishedWorkout = daySessions.contains { $0.workingSetCount > 0 }
        let metric = metrics.first { calendar.isDate($0.date, inSameDayAs: targetDay) }
        let sessionMaxHR = metric?.heartRateMax

        let daySetCount = daySessions.reduce(0) { $0 + $1.workingSetCount }
        let volumeComponent = volumeScore(
            daySetCount: daySetCount,
            chronicMean: baselines.chronicSetMean28d
        )

        let hrComponent = hrStrainScore(
            sessionMaxHR: sessionMaxHR,
            rhr60d: baselines.rhr60d,
            hrMax30d: baselines.hrMax30d,
            hasQualifyingWorkout: finishedWorkout || sessionMaxHR != nil
        )

        let rpeComponent = rpeScore(from: daySessions)

        let (value, source, hrUsed, confidence): (Double, ExertionScoreSource, Double?, Double)
        if let hr = hrComponent {
            if let volume = volumeComponent, volume > 0 {
                value = blended(hr: hr, volume: volume)
                source = .blended
                hrUsed = hr
                confidence = 0.9
            } else {
                value = hr
                source = .heartRate
                hrUsed = hr
                confidence = 0.85
            }
        } else if let rpe = rpeComponent {
            if let volume = volumeComponent, volume > 0 {
                value = blended(hr: rpe, volume: volume)
                source = .blended
                hrUsed = nil
                confidence = 0.7
            } else {
                value = rpe
                source = .rpe
                hrUsed = nil
                confidence = 0.65
            }
        } else if let volume = volumeComponent, volume > 0, finishedWorkout {
            value = volume
            source = .blended
            hrUsed = nil
            confidence = 0.5
        } else {
            return nil
        }

        Log.recovery.info(
            "exertion score=\(value, privacy: .public) hr=\(hrUsed ?? -1, privacy: .public) vol=\(volumeComponent ?? -1, privacy: .public) source=\(source.rawValue, privacy: .public)"
        )

        return ExertionScore(
            value: value,
            hrComponent: hrUsed,
            volumeComponent: volumeComponent,
            source: source,
            confidence: confidence,
            isCalibrated: baselines.isCalibrated
        )
    }

    static func workoutDaySessions(from sessions: [WorkoutSession], calendar: Calendar) -> [WorkoutDaySession] {
        sessions
            .filter { $0.endTime != nil }
            .map { session in
                var setCount = 0
                var rpeValues: [Double] = []
                for exercise in session.exercises {
                    for set in exercise.sets where set.isCompleted {
                        guard WorkoutSetType(storageValue: set.setType) != .warmup else { continue }
                        setCount += 1
                        if let rpe = set.rpe, rpe.isFinite {
                            rpeValues.append(rpe)
                        }
                    }
                }
                let meanRPE: Double? = rpeValues.isEmpty
                    ? nil
                    : WorkoutEffortScoreCalculator.clampAndRound(
                        rpeValues.reduce(0, +) / Double(rpeValues.count)
                    )
                return WorkoutDaySession(
                    date: calendar.startOfDay(for: session.date),
                    workingSetCount: setCount,
                    meanRPE: meanRPE,
                    hkEffortScore: nil
                )
            }
    }

    private static func blended(hr: Double, volume: Double) -> Double {
        ExertionHeuristics.hrStrainWeight * hr + ExertionHeuristics.volumeWeight * volume
    }

    private static func hrStrainScore(
        sessionMaxHR: Double?,
        rhr60d: Double?,
        hrMax30d: Double,
        hasQualifyingWorkout: Bool
    ) -> Double? {
        guard hasQualifyingWorkout,
              let sessionMaxHR,
              let rhr60d
        else { return nil }

        let denominator = hrMax30d - rhr60d
        guard denominator > 0 else { return nil }

        let strain = (sessionMaxHR - rhr60d) / denominator
        return min(100, max(0, strain * 100))
    }

    private static func volumeScore(daySetCount: Int, chronicMean: Double?) -> Double? {
        guard daySetCount > 0, let chronicMean, chronicMean > 0 else { return nil }
        let normalized = min(1, Double(daySetCount) / chronicMean)
        return normalized * 100
    }

    private static func rpeScore(from sessions: [WorkoutDaySession]) -> Double? {
        var values: [Double] = []
        for session in sessions {
            if let rpe = session.meanRPE {
                values.append(rpe)
            } else if let hk = session.hkEffortScore {
                values.append(hk)
            }
        }
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return min(100, max(0, mean * 10))
    }

    private static func hrMax30d(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> Double {
        let window = metricsInWindow(
            metrics: metrics,
            end: referenceDay,
            days: ExertionHeuristics.hrMaxWindowDays,
            calendar: calendar,
            excludingReferenceDay: false
        )
        let values = window.compactMap(\.heartRateMax)
        if let maxHR = values.max() {
            return max(maxHR, ExertionHeuristics.hrMaxFloor)
        }
        return ExertionHeuristics.hrMaxFloor
    }

    private static func rhr60d(
        metrics: [DailyMetricSnapshot],
        referenceDay: Date,
        calendar: Calendar
    ) -> Double? {
        let window = metricsInWindow(
            metrics: metrics,
            end: referenceDay,
            days: ExertionHeuristics.rhrWindowDays,
            calendar: calendar,
            excludingReferenceDay: false
        )
        return arithmeticMean(window.compactMap(\.restingHR))
    }

    private static func chronicSetMean28d(
        sessions: [WorkoutDaySession],
        referenceDay: Date,
        calendar: Calendar
    ) -> Double? {
        guard let chronicStart = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.chronicLoadWindowDays - 1),
            to: referenceDay
        ) else { return nil }

        var loadsByDay: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            guard day >= chronicStart, day <= referenceDay else { continue }
            loadsByDay[day, default: 0] += session.workingSetCount
        }
        guard !loadsByDay.isEmpty else { return nil }
        let total = Double(loadsByDay.values.reduce(0, +))
        return total / Double(ExertionHeuristics.chronicLoadWindowDays)
    }

    private static func isCalibrated(
        metrics: [DailyMetricSnapshot],
        sessions: [WorkoutDaySession],
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        guard let hrStart = calendar.date(
            byAdding: .day,
            value: -(ExertionHeuristics.hrMaxWindowDays - 1),
            to: referenceDay
        ) else { return false }

        let hrDays = metrics.filter { snapshot in
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= hrStart, day <= referenceDay else { return false }
            return snapshot.heartRateMax != nil
        }.count

        if hrDays >= ExertionHeuristics.calibrationMinHRDays {
            return true
        }

        let workoutCount = sessions.filter { session in
            let day = calendar.startOfDay(for: session.date)
            guard day >= hrStart, day <= referenceDay else { return false }
            return session.workingSetCount > 0
        }.count

        return workoutCount >= ExertionHeuristics.calibrationMinWorkouts
    }

    private static func metricsInWindow(
        metrics: [DailyMetricSnapshot],
        end: Date,
        days: Int,
        calendar: Calendar,
        excludingReferenceDay: Bool
    ) -> [DailyMetricSnapshot] {
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: end)
        else { return [] }

        return metrics.filter { snapshot in
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, day <= end else { return false }
            if excludingReferenceDay, calendar.isDate(day, inSameDayAs: end) {
                return false
            }
            return true
        }
    }

    private static func arithmeticMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
