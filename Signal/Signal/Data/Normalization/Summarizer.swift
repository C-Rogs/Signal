import Foundation
import os
import SwiftData

enum Summarizer: Sendable {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder = JSONDecoder()

    static func summarize(
        day: Date,
        metric: DailyMetric?,
        nutrition: DailyNutrition? = nil,
        workoutSummaries: [String] = [],
        appleWorkouts: [AppleWorkout] = [],
        calendar: Calendar = .current
    ) -> (summary: DailySummary, embeddingText: String) {
        let dayKey = Self.dayKey(for: day, calendar: calendar)
        let hevySummary = Self.workoutsSummary(from: workoutSummaries)
        let appleSummary = Self.appleWorkoutsSummary(from: appleWorkouts)
        let summary = DailySummary(
            date: dayKey,
            hrvSDNN: metric?.hrvSDNN_ms,
            restingHR: metric?.restingHR,
            activeEnergy: metric?.activeEnergy_kcal,
            sleepHours: metric?.sleepHours,
            bodyMassKg: metric?.bodyMassKg,
            vo2Max: metric?.vo2Max,
            respiratoryRate: metric?.respiratoryRate,
            wristTemperatureDeltaC: metric?.wristTemperatureDeltaC,
            bloodOxygenPct: metric?.bloodOxygenPct,
            heartRateMax: metric?.heartRateMax,
            heartRateAvg: metric?.heartRateAvg,
            stepCount: metric?.stepCount,
            basalEnergyKcal: metric?.basalEnergyKcal,
            bodyFatPercentage: metric?.bodyFatPercentage,
            leanBodyMassKg: metric?.leanBodyMassKg,
            walkingHeartRateAvg: metric?.walkingHeartRateAvg,
            appleExerciseMinutes: metric?.appleExerciseMinutes,
            appleStandHours: metric?.appleStandHours,
            physicalEffort: metric?.physicalEffort,
            timeInDaylightMin: metric?.timeInDaylightMin,
            sleepingBreathingDisturbances: metric?.sleepingBreathingDisturbances,
            bloodPressureSystolic: metric?.bloodPressureSystolic,
            bloodPressureDiastolic: metric?.bloodPressureDiastolic,
            dietaryEnergyKcal: nutrition?.dietaryEnergyKcal,
            proteinG: nutrition?.proteinG,
            carbsG: nutrition?.carbsG,
            fatTotalG: nutrition?.fatTotalG,
            fatSaturatedG: nutrition?.fatSaturatedG,
            fiberG: nutrition?.fiberG,
            sugarG: nutrition?.sugarG,
            sodiumMg: nutrition?.sodiumMg,
            workoutsSummary: hevySummary,
            appleWorkoutsSummary: appleSummary,
            recoveryScore: nil
        )
        let text = Self.embeddingText(for: summary)
        Log.import.debug("summarized dayKey=\(dayKey, privacy: .public) textChars=\(text.count, privacy: .public)")
        return (summary, text)
    }

    static func summarize(
        metric: DailyMetric,
        workoutSummaries: [String] = [],
        calendar: Calendar = .current
    ) -> (summary: DailySummary, embeddingText: String) {
        summarize(
            day: metric.date,
            metric: metric,
            workoutSummaries: workoutSummaries,
            calendar: calendar
        )
    }

    @MainActor
    static func summarize(
        metric: DailyMetric,
        workoutSessions: [WorkoutSession],
        calendar: Calendar = .current
    ) -> (summary: DailySummary, embeddingText: String) {
        let summaries = workoutSessions.map { renderSessionSummary($0) }
        return summarize(metric: metric, workoutSummaries: summaries, calendar: calendar)
    }

    static func renderAppleWorkoutSummary(_ workout: AppleWorkout) -> String {
        let minutes = workout.durationSec / 60
        var parts: [String] = [
            "\(workout.activityType) \(format(minutes, decimals: 0)) min",
        ]
        if let energy = workout.activeEnergyKcal {
            parts.append("\(format(energy, decimals: 0)) kcal")
        }
        if let distance = workout.distanceKm {
            parts.append("\(format(distance, decimals: 2)) km")
        }
        if let power = workout.avgRunningPowerW {
            parts.append("power \(format(power, decimals: 0)) W")
        }
        if let stride = workout.avgStrideLengthM {
            parts.append("stride \(format(stride, decimals: 2)) m")
        }
        if let speed = workout.avgRunningSpeedMps {
            parts.append("speed \(format(speed, decimals: 2)) m/s")
        }
        return parts.joined(separator: ", ")
    }

    static func renderSessionSummary(_ session: WorkoutSession) -> String {
        let exercises = session.exercises.sorted { $0.order < $1.order }
        let parts = exercises.map { renderExerciseSummary($0) }.filter { !$0.isEmpty }
        if parts.isEmpty {
            return session.title
        }
        return "\(session.title): \(parts.joined(separator: ", "))"
    }

    static func renderExerciseSummary(_ exercise: WorkoutExercise) -> String {
        let title = exercise.exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "" }

        let sortedSets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        let warmups = sortedSets.filter { isWarmup($0) }
        let working = sortedSets.filter { !isWarmup($0) }

        var segments: [String] = []
        if !warmups.isEmpty {
            segments.append("warmup \(renderSetGroup(warmups))")
        }
        if !working.isEmpty {
            segments.append(renderWorkingSets(working))
        } else if segments.isEmpty, !sortedSets.isEmpty {
            segments.append(renderSetGroup(sortedSets))
        }

        var line = title
        if let notes = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            line += " (\(notes))"
        }
        guard !segments.isEmpty else { return line }
        return "\(line): \(segments.joined(separator: "; "))"
    }

    static func renderExerciseSummary(parsed: HevyParsedExercise) -> String {
        let exercise = WorkoutExercise(
            exerciseTitle: parsed.exerciseTitle,
            notes: parsed.notes,
            supersetId: parsed.supersetId,
            order: parsed.order
        )
        for parsedSet in parsed.sets {
            let entry = SetEntry(
                setIndex: parsedSet.setIndex,
                setType: parsedSet.setType,
                weightKg: parsedSet.weightKg,
                reps: parsedSet.reps,
                distanceKm: parsedSet.distanceKm,
                durationSeconds: parsedSet.durationSeconds,
                rpe: parsedSet.rpe
            )
            exercise.sets.append(entry)
        }
        return renderExerciseSummary(exercise)
    }

    private static func renderWorkingSets(_ sets: [SetEntry]) -> String {
        let chunks = compressWorkingSets(sets)
        return chunks.joined(separator: ", ")
    }

    private static func compressWorkingSets(_ sets: [SetEntry]) -> [String] {
        guard !sets.isEmpty else { return [] }

        struct Chunk {
            var sets: [SetEntry]
        }

        var chunks: [Chunk] = []
        for set in sets {
            if let last = chunks.last, canMerge(last.sets.last!, set) {
                chunks[chunks.count - 1].sets.append(set)
            } else {
                chunks.append(Chunk(sets: [set]))
            }
        }

        return chunks.map { chunk in
            let reps = chunk.sets.compactMap(\.reps)
            let weights = chunk.sets.compactMap(\.weightKg)
            let count = chunk.sets.count
            let rpeSuffix = rpeRangeSuffix(chunk.sets)

            if weights.count == count, Set(weights).count == 1, Set(reps).count == 1, let reps = reps.first, let weight = weights.first {
                return "\(count) x \(reps) @ \(formatWeight(weight))kg\(rpeSuffix)"
            }

            if weights.count == count, Set(weights).count == 1, let weight = weights.first, reps.count == count {
                let repList = reps.map(String.init).joined(separator: "/")
                return "\(formatWeight(weight))kg x \(repList)\(rpeSuffix)"
            }

            return renderSetGroup(chunk.sets) + rpeSuffix
        }
    }

    private static func canMerge(_ left: SetEntry, _ right: SetEntry) -> Bool {
        left.weightKg == right.weightKg && left.reps == right.reps
    }

    private static func renderSetGroup(_ sets: [SetEntry]) -> String {
        sets.map { renderSingleSet($0) }.joined(separator: ", ")
    }

    private static func renderSingleSet(_ set: SetEntry) -> String {
        if let weight = set.weightKg, let reps = set.reps {
            return "\(formatWeight(weight))kg x \(reps)"
        }
        if let reps = set.reps {
            return "\(reps) reps"
        }
        if let km = set.distanceKm {
            return "\(formatWeight(km)) km"
        }
        if let seconds = set.durationSeconds, seconds > 0 {
            return "\(seconds)s"
        }
        return "logged"
    }

    private static func rpeRangeSuffix(_ sets: [SetEntry]) -> String {
        let values = sets.compactMap(\.rpe)
        guard !values.isEmpty else { return "" }
        let minValue = values.min()!
        let maxValue = values.max()!
        if minValue == maxValue {
            return " (RPE \(formatRPE(minValue)))"
        }
        return " (RPE \(formatRPE(minValue)) to \(formatRPE(maxValue)))"
    }

    private static func isWarmup(_ set: SetEntry) -> Bool {
        let normalized = set.setType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "warmup" || normalized == "warm_up"
    }

    private static func workoutsSummary(from workoutSummaries: [String]) -> String? {
        let parts = workoutSummaries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ")
    }

    private static func appleWorkoutsSummary(from workouts: [AppleWorkout]) -> String? {
        let parts = workouts.map { renderAppleWorkoutSummary($0) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ")
    }

    private static func embeddingText(for summary: DailySummary) -> String {
        var segments: [String] = ["Health day \(summary.date)."]

        if let hrvSDNN = summary.hrvSDNN {
            segments.append("HRV SDNN \(format(hrvSDNN, decimals: 1)) ms.")
        }
        if let restingHR = summary.restingHR {
            segments.append("Resting HR \(format(restingHR, decimals: 0)) bpm.")
        }
        if let sleepHours = summary.sleepHours {
            segments.append("Sleep \(format(sleepHours, decimals: 2)) hours.")
        }
        if let respiratoryRate = summary.respiratoryRate {
            segments.append("Sleep respiratory rate \(format(respiratoryRate, decimals: 1)) brpm.")
        }
        if let wristTemperatureDeltaC = summary.wristTemperatureDeltaC {
            segments.append("Sleep wrist temperature delta \(format(wristTemperatureDeltaC, decimals: 2)) C.")
        }
        if let bloodOxygenPct = summary.bloodOxygenPct {
            segments.append("Sleep blood oxygen \(format(bloodOxygenPct, decimals: 1)) pct.")
        }
        if let sleepingBreathingDisturbances = summary.sleepingBreathingDisturbances {
            segments.append(
                "Sleep breathing disturbances \(format(sleepingBreathingDisturbances, decimals: 0))."
            )
        }

        if let activeEnergy = summary.activeEnergy {
            segments.append("Active energy \(format(activeEnergy, decimals: 0)) kcal.")
        }
        if let stepCount = summary.stepCount {
            segments.append("Steps \(format(stepCount, decimals: 0)).")
        }
        if let appleExerciseMinutes = summary.appleExerciseMinutes {
            segments.append("Exercise minutes \(format(appleExerciseMinutes, decimals: 0)).")
        }
        if let appleStandHours = summary.appleStandHours {
            segments.append("Stand hours \(format(appleStandHours, decimals: 0)).")
        }
        if let physicalEffort = summary.physicalEffort {
            segments.append("Physical effort \(format(physicalEffort, decimals: 2)) kcal/hr/kg.")
        }
        if let timeInDaylightMin = summary.timeInDaylightMin {
            segments.append("Daylight \(format(timeInDaylightMin, decimals: 0)) min.")
        }

        if let heartRateMax = summary.heartRateMax {
            segments.append("Heart rate max \(format(heartRateMax, decimals: 0)) bpm.")
        }
        if let heartRateAvg = summary.heartRateAvg {
            segments.append("Heart rate avg \(format(heartRateAvg, decimals: 0)) bpm.")
        }
        if let walkingHeartRateAvg = summary.walkingHeartRateAvg {
            segments.append("Walking HR avg \(format(walkingHeartRateAvg, decimals: 0)) bpm.")
        }
        if let bodyMassKg = summary.bodyMassKg {
            segments.append("Body mass \(format(bodyMassKg, decimals: 1)) kg.")
        }
        if let bodyFatPercentage = summary.bodyFatPercentage {
            segments.append("Body fat \(format(bodyFatPercentage, decimals: 1)) pct.")
        }
        if let leanBodyMassKg = summary.leanBodyMassKg {
            segments.append("Lean mass \(format(leanBodyMassKg, decimals: 1)) kg.")
        }
        if let vo2Max = summary.vo2Max {
            segments.append("VO2 max \(format(vo2Max, decimals: 1)) ml/kg/min.")
        }
        if let basalEnergyKcal = summary.basalEnergyKcal {
            segments.append("Basal energy \(format(basalEnergyKcal, decimals: 0)) kcal.")
        }

        if let nutritionLine = nutritionLine(for: summary) {
            segments.append(nutritionLine)
        }

        if let systolic = summary.bloodPressureSystolic, let diastolic = summary.bloodPressureDiastolic {
            segments.append(
                "Blood pressure \(format(systolic, decimals: 0))/\(format(diastolic, decimals: 0)) mmHg."
            )
        }

        if let workoutsSummary = summary.workoutsSummary {
            segments.append("Hevy workouts: \(workoutsSummary).")
        }
        if let appleWorkoutsSummary = summary.appleWorkoutsSummary {
            segments.append("Apple workouts: \(appleWorkoutsSummary).")
        }
        if let recoveryScore = summary.recoveryScore {
            segments.append("Recovery score \(format(recoveryScore, decimals: 0)).")
        }
        return segments.joined(separator: " ")
    }

    private static func nutritionLine(for summary: DailySummary) -> String? {
        var parts: [String] = []
        if let dietaryEnergyKcal = summary.dietaryEnergyKcal {
            parts.append("\(format(dietaryEnergyKcal, decimals: 0)) kcal")
        }
        if let proteinG = summary.proteinG {
            parts.append("\(format(proteinG, decimals: 0)) g protein")
        }
        if let carbsG = summary.carbsG {
            parts.append("\(format(carbsG, decimals: 0)) g carbs")
        }
        if let fatTotalG = summary.fatTotalG {
            parts.append("\(format(fatTotalG, decimals: 0)) g fat")
        }
        if let fiberG = summary.fiberG {
            parts.append("\(format(fiberG, decimals: 0)) g fiber")
        }
        if let sugarG = summary.sugarG {
            parts.append("\(format(sugarG, decimals: 0)) g sugar")
        }
        if let sodiumMg = summary.sodiumMg {
            parts.append("\(format(sodiumMg, decimals: 0)) mg sodium")
        }
        guard !parts.isEmpty else { return nil }
        return "Nutrition: \(parts.joined(separator: ", "))."
    }

    private static func formatWeight(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func formatRPE(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func encodeJSON(_ summary: DailySummary) throws -> Data {
        try jsonEncoder.encode(summary)
    }

    static func decodeJSON(_ data: Data) throws -> DailySummary {
        try jsonDecoder.decode(DailySummary.self, from: data)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        let month = calendar.component(.month, from: day)
        let dayOfMonth = calendar.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
