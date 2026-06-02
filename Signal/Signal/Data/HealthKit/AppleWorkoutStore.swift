import Foundation
import HealthKit
import SwiftData
import os

enum AppleWorkoutStore {
    static let healthKitLiveSource = "healthkit"
    static let exportSource = "apple-health-export"

    @MainActor
    static func upsert(_ workout: AppleWorkout, in context: ModelContext) throws {
        let id = workout.stableID
        var descriptor = FetchDescriptor<AppleWorkout>(
            predicate: #Predicate { $0.stableID == id }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.activityType = workout.activityType
            existing.startDate = workout.startDate
            existing.endDate = workout.endDate
            existing.durationSec = workout.durationSec
            existing.activeEnergyKcal = workout.activeEnergyKcal
            existing.distanceKm = workout.distanceKm
            existing.avgRunningPowerW = workout.avgRunningPowerW
            existing.avgStrideLengthM = workout.avgStrideLengthM
            existing.avgVerticalOscillationCm = workout.avgVerticalOscillationCm
            existing.avgGroundContactMs = workout.avgGroundContactMs
            existing.avgRunningSpeedMps = workout.avgRunningSpeedMps
            existing.source = workout.source
        } else {
            context.insert(workout)
        }
    }

    @MainActor
    static func upsertBatch(_ workouts: [AppleWorkout], in context: ModelContext) throws -> Int {
        guard !workouts.isEmpty else { return 0 }
        for workout in workouts {
            try upsert(workout, in: context)
        }
        try context.save()
        return workouts.count
    }

    @MainActor
    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<AppleWorkout>())
    }

    @MainActor
    static func fetchWorkouts(
        for dayStart: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> [AppleWorkout] {
        let day = calendar.startOfDay(for: dayStart)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else {
            return []
        }
        let descriptor = FetchDescriptor<AppleWorkout>(
            predicate: #Predicate { $0.startDate >= day && $0.startDate < dayEnd },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
}

struct RunMechanicsAverages: Sendable, Equatable {
    var avgRunningPowerW: Double?
    var avgStrideLengthM: Double?
    var avgVerticalOscillationCm: Double?
    var avgGroundContactMs: Double?
    var avgRunningSpeedMps: Double?
}

enum AppleWorkoutMapper {
    static func stableID(
        activityType: String,
        startDate: Date,
        source: String
    ) -> String {
        let start = startDate.timeIntervalSince1970
        return "\(source)|\(activityType)|\(start)"
    }

    static func isRunningActivity(_ activityType: String) -> Bool {
        activityType == "Running" || activityType == "HKWorkoutActivityTypeRunning"
    }

    static func from(
        hkWorkout: HKWorkout,
        mechanics: RunMechanicsAverages = RunMechanicsAverages(),
        source: String = AppleWorkoutStore.healthKitLiveSource
    ) -> AppleWorkout? {
        let duration = hkWorkout.duration
        guard duration.isFinite, duration > 0 else { return nil }
        let typeName = hkWorkout.workoutActivityType.displayName
        let energy = activeEnergyKcal(from: hkWorkout)
        let distance = distanceKm(from: hkWorkout)
        var runMechanics = mechanics
        if isRunningActivity(typeName) {
            runMechanics = mergeRunMechanics(
                from: hkWorkout,
                existing: mechanics
            )
        } else {
            runMechanics = RunMechanicsAverages()
        }
        return AppleWorkout(
            stableID: stableID(
                activityType: typeName,
                startDate: hkWorkout.startDate,
                source: source
            ),
            activityType: typeName,
            startDate: hkWorkout.startDate,
            endDate: hkWorkout.endDate,
            durationSec: duration,
            activeEnergyKcal: energy,
            distanceKm: distance,
            avgRunningPowerW: runMechanics.avgRunningPowerW,
            avgStrideLengthM: runMechanics.avgStrideLengthM,
            avgVerticalOscillationCm: runMechanics.avgVerticalOscillationCm,
            avgGroundContactMs: runMechanics.avgGroundContactMs,
            avgRunningSpeedMps: runMechanics.avgRunningSpeedMps,
            source: source
        )
    }

    static func fromExportAttributes(
        _ attributes: [String: String],
        mechanics: RunMechanicsAverages = RunMechanicsAverages()
    ) -> AppleWorkout? {
        guard let type = attributes["workoutActivityType"],
              let startString = attributes["startDate"],
              let start = AppleHealthDateParser.parse(startString)
        else {
            return nil
        }

        let end: Date
        if let endString = attributes["endDate"], let parsedEnd = AppleHealthDateParser.parse(endString) {
            end = parsedEnd
        } else if let durationString = attributes["duration"],
                  let durationValue = Double(durationString)
        {
            let unit = attributes["durationUnit"]?.lowercased() ?? "s"
            let seconds = normalizedDurationSeconds(value: durationValue, unit: unit)
            end = start.addingTimeInterval(seconds)
        } else {
            return nil
        }

        let durationSec = max(0, end.timeIntervalSince(start))
        guard durationSec > 0 else { return nil }

        let energy = normalizedEnergyKcal(
            valueString: attributes["totalEnergyBurned"],
            unit: attributes["totalEnergyBurnedUnit"]
        )
        let distance = normalizedDistanceKm(
            valueString: attributes["totalDistance"],
            unit: attributes["totalDistanceUnit"]
        )

        let displayType = displayWorkoutTypeName(type)
        let runMechanics = isRunningActivity(displayType) ? mechanics : RunMechanicsAverages()
        return AppleWorkout(
            stableID: stableID(
                activityType: displayType,
                startDate: start,
                source: AppleWorkoutStore.exportSource
            ),
            activityType: displayType,
            startDate: start,
            endDate: end,
            durationSec: durationSec,
            activeEnergyKcal: energy,
            distanceKm: distance,
            avgRunningPowerW: runMechanics.avgRunningPowerW,
            avgStrideLengthM: runMechanics.avgStrideLengthM,
            avgVerticalOscillationCm: runMechanics.avgVerticalOscillationCm,
            avgGroundContactMs: runMechanics.avgGroundContactMs,
            avgRunningSpeedMps: runMechanics.avgRunningSpeedMps,
            source: AppleWorkoutStore.exportSource
        )
    }

    static func mergeRunMechanics(
        from workout: HKWorkout,
        existing: RunMechanicsAverages
    ) -> RunMechanicsAverages {
        var merged = existing
        merged.avgRunningPowerW = merged.avgRunningPowerW ?? averageQuantity(
            workout,
            identifier: .runningPower,
            unit: .watt()
        )
        merged.avgStrideLengthM = merged.avgStrideLengthM ?? averageQuantity(
            workout,
            identifier: .runningStrideLength,
            unit: .meter()
        )
        merged.avgVerticalOscillationCm = merged.avgVerticalOscillationCm ?? averageQuantity(
            workout,
            identifier: .runningVerticalOscillation,
            unit: .meterUnit(with: .centi)
        )
        merged.avgGroundContactMs = merged.avgGroundContactMs ?? averageQuantity(
            workout,
            identifier: .runningGroundContactTime,
            unit: .secondUnit(with: .milli)
        )
        if merged.avgRunningSpeedMps == nil {
            merged.avgRunningSpeedMps = averageRunningSpeedMps(from: workout)
        }
        return merged
    }

    private static func averageRunningSpeedMps(from workout: HKWorkout) -> Double? {
        if let metersPerSecond = averageQuantity(
            workout,
            identifier: .runningSpeed,
            unit: .meter().unitDivided(by: .second())
        ) {
            return metersPerSecond
        }
        if let kmPerHour = averageQuantity(
            workout,
            identifier: .runningSpeed,
            unit: HKUnit.meter().unitDivided(by: .hour()).unitMultiplied(by: HKUnit.gramUnit(with: .kilo))
        ) {
            return kmPerHour / 3.6
        }
        return nil
    }

    static func mechanicsFromWorkoutStatistics(_ stats: [String: String]) -> RunMechanicsAverages {
        var mechanics = RunMechanicsAverages()
        for (type, averageString) in stats {
            guard let average = Double(averageString) else { continue }
            switch type {
            case "HKQuantityTypeIdentifierRunningPower":
                mechanics.avgRunningPowerW = average
            case "HKQuantityTypeIdentifierRunningStrideLength":
                mechanics.avgStrideLengthM = average
            case "HKQuantityTypeIdentifierRunningVerticalOscillation":
                mechanics.avgVerticalOscillationCm = average
            case "HKQuantityTypeIdentifierRunningGroundContactTime":
                mechanics.avgGroundContactMs = average
            case "HKQuantityTypeIdentifierRunningSpeed":
                mechanics.avgRunningSpeedMps = average / 3.6
            default:
                break
            }
        }
        return mechanics
    }

    static func meanRunningRecordFallback(
        type: String,
        start: Date,
        end: Date,
        samples: [RunningRecordSample]
    ) -> Double? {
        let values = samples.filter { sample in
            sample.type == type && sample.date >= start && sample.date <= end
        }.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func applyRecordFallback(
        to mechanics: inout RunMechanicsAverages,
        workoutStart: Date,
        workoutEnd: Date,
        samples: [RunningRecordSample]
    ) {
        if mechanics.avgRunningPowerW == nil {
            mechanics.avgRunningPowerW = meanRunningRecordFallback(
                type: "HKQuantityTypeIdentifierRunningPower",
                start: workoutStart,
                end: workoutEnd,
                samples: samples
            )
        }
        if mechanics.avgStrideLengthM == nil {
            mechanics.avgStrideLengthM = meanRunningRecordFallback(
                type: "HKQuantityTypeIdentifierRunningStrideLength",
                start: workoutStart,
                end: workoutEnd,
                samples: samples
            )
        }
        if mechanics.avgVerticalOscillationCm == nil {
            mechanics.avgVerticalOscillationCm = meanRunningRecordFallback(
                type: "HKQuantityTypeIdentifierRunningVerticalOscillation",
                start: workoutStart,
                end: workoutEnd,
                samples: samples
            )
        }
        if mechanics.avgGroundContactMs == nil {
            mechanics.avgGroundContactMs = meanRunningRecordFallback(
                type: "HKQuantityTypeIdentifierRunningGroundContactTime",
                start: workoutStart,
                end: workoutEnd,
                samples: samples
            )
        }
        if mechanics.avgRunningSpeedMps == nil,
           let kmPerHour = meanRunningRecordFallback(
               type: "HKQuantityTypeIdentifierRunningSpeed",
               start: workoutStart,
               end: workoutEnd,
               samples: samples
           )
        {
            mechanics.avgRunningSpeedMps = kmPerHour / 3.6
        }
    }

    private static func averageQuantity(
        _ workout: HKWorkout,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) -> Double? {
        guard let quantity = workout.statistics(for: HKQuantityType(identifier))?.averageQuantity() else {
            return nil
        }
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func displayWorkoutTypeName(_ exportType: String) -> String {
        if exportType.hasPrefix("HKWorkoutActivityType") {
            let suffix = exportType.dropFirst("HKWorkoutActivityType".count)
            return String(suffix)
        }
        return exportType
    }

    private static func normalizedDurationSeconds(value: Double, unit: String) -> TimeInterval {
        switch unit {
        case "min", "minute", "minutes":
            return value * 60
        case "hr", "hour", "hours":
            return value * 3600
        default:
            return value
        }
    }

    private static func normalizedEnergyKcal(valueString: String?, unit: String?) -> Double? {
        guard let valueString, let raw = Double(valueString) else { return nil }
        return AppleHealthUnitNormalizer.normalizedActiveEnergyKcal(value: raw, unit: unit)
    }

    private static func normalizedDistanceKm(valueString: String?, unit: String?) -> Double? {
        guard let valueString, let raw = Double(valueString) else { return nil }
        guard let unit, !unit.isEmpty else { return raw }
        switch unit.lowercased() {
        case "km":
            return raw
        case "m", "meter", "meters":
            return raw / 1000
        case "mi", "mile", "miles":
            return raw * 1.60934
        default:
            Log.import.warning("unexpected workout distance unit=\(unit, privacy: .public); skipped distance")
            return nil
        }
    }

    private static func activeEnergyKcal(from workout: HKWorkout) -> Double? {
        guard let quantity = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
        else {
            return nil
        }
        return HealthKitSampleIngestor.normalizedActiveEnergyKcal(from: quantity)
    }

    private static func distanceKm(from workout: HKWorkout) -> Double? {
        guard let quantity = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
        else {
            return nil
        }
        let meters = quantity.doubleValue(for: .meter())
        guard meters.isFinite, meters > 0 else { return nil }
        return meters / 1000
    }
}

struct RunningRecordSample: Sendable {
    let type: String
    let value: Double
    let date: Date
}

private extension HKWorkoutActivityType {
    var displayName: String {
        if self == .running {
            return "Running"
        }
        let raw = String(describing: self)
        if raw.hasPrefix("HKWorkoutActivityType") {
            return String(raw.dropFirst("HKWorkoutActivityType".count))
        }
        return raw
    }
}
