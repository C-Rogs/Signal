import Foundation
import SwiftData

enum ProgressionIntent: Sendable, Equatable {
    case hold
    case increase(byKg: Double)
    case deload

    var chipLabel: String {
        switch self {
        case .hold:
            return "Matches planned hold"
        case .increase(let byKg):
            let formatted = byKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", byKg)
                : String(format: "%.1f", byKg)
            return "Matches planned progression (+\(formatted) kg intent)"
        case .deload:
            return "Deload intent: hold or reduce load"
        }
    }
}

struct SwapSetTemplate: Sendable, Equatable {
    let setIndex: Int
    let setType: String
    let weightKg: Double?
    let reps: Int?
    let distanceKm: Double?
    let durationSeconds: Int?
}

struct SwapSetPlan: Sendable, Equatable {
    let sets: [SwapSetTemplate]
    let progressionIntent: ProgressionIntent
    let substituteHasHistory: Bool
    let noHistoryNote: String?

    static let noHistoryMessage =
        "No prior log for this lift; enter weight from feel."
}

@MainActor
enum ExerciseSwapLoadPrescription {
    static func build(
        source: WorkoutExercise,
        substitute: ExerciseCatalog,
        recoveryScore: RecoveryScore?,
        personalReadiness: PersonalReadinessProfile?,
        deloadActive: Bool,
        in context: ModelContext
    ) throws -> SwapSetPlan {
        let mode = ExerciseLoggingMode.from(catalogEntry: substitute)
        let sourceMode = ExerciseLoggingMode.from(catalogEntry: source.catalogEntry)
        let progression = try deriveProgressionIntent(
            source: source,
            mode: sourceMode,
            recoveryScore: recoveryScore,
            personalReadiness: personalReadiness,
            deloadActive: deloadActive,
            in: context
        )

        let substituteHistory = try LastSessionAutofill.templates(
            catalogEntry: substitute,
            exerciseTitle: substitute.canonicalName,
            mode: mode,
            in: context
        )
        let hasHistory = substituteHistory.contains {
            $0.weightKg != nil || $0.reps != nil || $0.distanceKm != nil
        }

        let remainingStructure = remainingSetStructure(from: source)
        let sets: [SwapSetTemplate]

        if hasHistory {
            sets = try buildSetsPreservingStructure(
                remainingStructure: remainingStructure,
                substitute: substitute,
                substituteHistory: substituteHistory,
                progression: progression,
                mode: mode,
                in: context
            )
        } else {
            sets = remainingStructure.enumerated().map { offset, slot in
                SwapSetTemplate(
                    setIndex: offset,
                    setType: slot.setType,
                    weightKg: mode == .strength ? nil : nil,
                    reps: slot.reps ?? (mode == .strength ? nil : nil),
                    distanceKm: mode == .cardio ? slot.distanceKm : nil,
                    durationSeconds: mode == .cardio ? slot.durationSeconds : nil
                )
            }
        }

        return SwapSetPlan(
            sets: sets,
            progressionIntent: progression,
            substituteHasHistory: hasHistory,
            noHistoryNote: hasHistory ? nil : SwapSetPlan.noHistoryMessage
        )
    }

    private struct SetSlot: Sendable {
        let setType: String
        let reps: Int?
        let distanceKm: Double?
        let durationSeconds: Int?
        let isWarmup: Bool
    }

    private static func remainingSetStructure(from source: WorkoutExercise) -> [SetSlot] {
        source.sets
            .sorted { $0.setIndex < $1.setIndex }
            .filter { !$0.isCompleted }
            .map { set in
                SetSlot(
                    setType: set.setType,
                    reps: set.reps,
                    distanceKm: set.distanceKm,
                    durationSeconds: set.durationSeconds,
                    isWarmup: WorkoutSetType(storageValue: set.setType) == .warmup
                )
            }
    }

    private static func deriveProgressionIntent(
        source: WorkoutExercise,
        mode: ExerciseLoggingMode,
        recoveryScore: RecoveryScore?,
        personalReadiness: PersonalReadinessProfile?,
        deloadActive: Bool,
        in context: ModelContext
    ) throws -> ProgressionIntent {
        if deloadActive {
            return .deload
        }

        if let recoveryScore {
            let band = RecoveryLoadBand.band(
                for: RecoveryBandContext(score: recoveryScore, profile: personalReadiness)
            )
            if band == .low {
                return .hold
            }
        }

        guard mode == .strength else { return .hold }

        let lastTemplates = try LastSessionAutofill.templates(
            catalogEntry: source.catalogEntry,
            exerciseTitle: source.exerciseTitle,
            mode: mode,
            in: context
        )
        let lastWorking = lastTemplates.first {
            WorkoutSetType(storageValue: $0.setType) != .warmup && $0.weightKg != nil
        }
        let plannedWorking = source.sets
            .sorted { $0.setIndex < $1.setIndex }
            .first {
                !$0.isCompleted
                    && WorkoutSetType(storageValue: $0.setType) != .warmup
                    && $0.weightKg != nil
            }

        guard let planned = plannedWorking?.weightKg,
              let lastWeight = lastWorking?.weightKg
        else {
            return .hold
        }

        let delta = planned - lastWeight
        if delta >= LiveLoadAutoregulation.suggestedLoadIncrementKg - 0.01 {
            return .increase(byKg: LiveLoadAutoregulation.suggestedLoadIncrementKg)
        }
        return .hold
    }

    private static func buildSetsPreservingStructure(
        remainingStructure: [SetSlot],
        substitute: ExerciseCatalog,
        substituteHistory: [SetAutofillTemplate],
        progression: ProgressionIntent,
        mode: ExerciseLoggingMode,
        in context: ModelContext
    ) throws -> [SwapSetTemplate] {
        _ = context
        let workingHistory = substituteHistory.filter {
            WorkoutSetType(storageValue: $0.setType) != .warmup
        }
        var workingIndex = 0

        return remainingStructure.enumerated().map { offset, slot in
            if slot.isWarmup {
                let warmupTemplate = substituteHistory.first {
                    WorkoutSetType(storageValue: $0.setType) == .warmup
                }
                return SwapSetTemplate(
                    setIndex: offset,
                    setType: slot.setType,
                    weightKg: warmupTemplate?.weightKg,
                    reps: slot.reps ?? warmupTemplate?.reps,
                    distanceKm: slot.distanceKm ?? warmupTemplate?.distanceKm,
                    durationSeconds: slot.durationSeconds ?? warmupTemplate?.durationSeconds
                )
            }

            let historyTemplate: SetAutofillTemplate?
            if workingIndex < workingHistory.count {
                historyTemplate = workingHistory[workingIndex]
                workingIndex += 1
            } else {
                historyTemplate = workingHistory.last
            }

            let baseWeight = historyTemplate?.weightKg
            let adjustedWeight = applyProgression(to: baseWeight, intent: progression, mode: mode)

            return SwapSetTemplate(
                setIndex: offset,
                setType: slot.setType,
                weightKg: adjustedWeight,
                reps: slot.reps ?? historyTemplate?.reps,
                distanceKm: slot.distanceKm ?? historyTemplate?.distanceKm,
                durationSeconds: slot.durationSeconds ?? historyTemplate?.durationSeconds
            )
        }
    }

    private static func applyProgression(
        to baseWeight: Double?,
        intent: ProgressionIntent,
        mode: ExerciseLoggingMode
    ) -> Double? {
        guard mode == .strength, let baseWeight else { return baseWeight }
        switch intent {
        case .hold, .deload:
            return roundToPlateIncrement(baseWeight)
        case .increase(let byKg):
            return roundToPlateIncrement(baseWeight + byKg)
        }
    }

    private static func roundToPlateIncrement(_ kg: Double) -> Double {
        let step = LiveLoadAutoregulation.suggestedLoadIncrementKg
        return (kg / step).rounded() * step
    }
}
