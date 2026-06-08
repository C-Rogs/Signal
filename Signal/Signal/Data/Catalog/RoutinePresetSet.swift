import Foundation
import SwiftData

@Model
final class RoutinePresetSet {
    var setIndex: Int
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var distanceKm: Double?
    var durationSeconds: Int?
    var rpe: Double?
    var prescriptionNote: String?
    var restDurationSeconds: Int?

    var routineExercise: RoutineExercise?

    init(
        setIndex: Int,
        setType: String,
        weightKg: Double? = nil,
        reps: Int? = nil,
        distanceKm: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil,
        prescriptionNote: String? = nil,
        restDurationSeconds: Int? = nil
    ) {
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.prescriptionNote = prescriptionNote
        self.restDurationSeconds = restDurationSeconds
    }
}

extension RoutinePresetSet {
    func asAutofillTemplate() -> SetAutofillTemplate {
        SetAutofillTemplate(
            setIndex: setIndex,
            setType: setType,
            weightKg: weightKg,
            reps: reps,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            rpe: rpe,
            prescriptionNote: prescriptionNote,
            restDurationSeconds: restDurationSeconds
        )
    }

    static func from(parsed: ParsedWorkoutSet, setIndex: Int) -> RoutinePresetSet {
        RoutinePresetSet(
            setIndex: setIndex,
            setType: parsed.isWarmup
                ? WorkoutSetType.warmup.storageValue
                : WorkoutSetType.normal.storageValue,
            weightKg: parsed.weightKg,
            reps: parsed.reps,
            distanceKm: nil,
            durationSeconds: nil,
            rpe: parsed.rpe,
            prescriptionNote: parsed.prescriptionNote,
            restDurationSeconds: parsed.restDurationSeconds
        )
    }
}
