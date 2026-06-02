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
            existing.workoutTypeName = workout.workoutTypeName
            existing.startDate = workout.startDate
            existing.endDate = workout.endDate
            existing.durationSec = workout.durationSec
            existing.activeEnergyKcal = workout.activeEnergyKcal
            existing.distanceKm = workout.distanceKm
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
}

enum AppleWorkoutMapper {
    static func stableID(
        workoutTypeName: String,
        startDate: Date,
        endDate: Date,
        source: String
    ) -> String {
        let start = startDate.timeIntervalSince1970
        let end = endDate.timeIntervalSince1970
        return "\(source)|\(workoutTypeName)|\(start)|\(end)"
    }

    static func from(
        hkWorkout: HKWorkout,
        source: String = AppleWorkoutStore.healthKitLiveSource
    ) -> AppleWorkout? {
        let duration = hkWorkout.duration
        guard duration.isFinite, duration > 0 else { return nil }
        let typeName = hkWorkout.workoutActivityType.name
        let energy = activeEnergyKcal(from: hkWorkout)
        let distance = distanceKm(from: hkWorkout)
        return AppleWorkout(
            stableID: stableID(
                workoutTypeName: typeName,
                startDate: hkWorkout.startDate,
                endDate: hkWorkout.endDate,
                source: source
            ),
            workoutTypeName: typeName,
            startDate: hkWorkout.startDate,
            endDate: hkWorkout.endDate,
            durationSec: duration,
            activeEnergyKcal: energy,
            distanceKm: distance,
            source: source
        )
    }

    static func fromExportAttributes(_ attributes: [String: String]) -> AppleWorkout? {
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
        return AppleWorkout(
            stableID: stableID(
                workoutTypeName: displayType,
                startDate: start,
                endDate: end,
                source: AppleWorkoutStore.exportSource
            ),
            workoutTypeName: displayType,
            startDate: start,
            endDate: end,
            durationSec: durationSec,
            activeEnergyKcal: energy,
            distanceKm: distance,
            source: AppleWorkoutStore.exportSource
        )
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

private extension HKWorkoutActivityType {
    var name: String {
        String(describing: self)
    }
}
