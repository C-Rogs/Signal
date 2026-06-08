import Foundation
import os
import SwiftData

@MainActor
final class RoutineTemplateStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func createRoutine(name: String, from request: ParsedPlanStartRequest) throws -> Routine {
        let routine = Routine(name: name)
        context.insert(routine)

        for (index, exercise) in request.exercises.enumerated() {
            let slot = RoutineExercise(
                order: index,
                exerciseTitleFallback: exercise.catalogEntry == nil ? exercise.exerciseTitle : nil,
                catalogEntry: exercise.catalogEntry,
                restDurationSeconds: exercise.restDurationSeconds ?? 90,
                autoStartRestOnSetComplete: true
            )
            slot.routine = routine
            routine.exercises.append(slot)

            for (offset, parsedSet) in exercise.sets.enumerated() {
                let preset = RoutinePresetSet.from(parsed: parsedSet, setIndex: offset)
                preset.routineExercise = slot
                slot.presetSets.append(preset)
            }
        }

        try context.save()
        let presetCount = totalPresetSetCount(for: routine)
        Log.workout.info(
            "created routine name=\(name, privacy: .public) exercises=\(request.exercises.count, privacy: .public) presetSets=\(presetCount, privacy: .public)"
        )
        return routine
    }

    func presetTemplates(for slot: RoutineExercise) -> [SetAutofillTemplate] {
        slot.sortedPresetSets.map { $0.asAutofillTemplate() }
    }

    func totalPresetSetCount(for routine: Routine) -> Int {
        routine.totalPresetSetCount
    }
}
