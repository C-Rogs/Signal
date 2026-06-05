import Foundation
import SwiftData

@MainActor
final class ExerciseSessionHintCache {
    private struct Entry {
        let lastHint: String?
        let previousHints: [Int: String?]
        let templates: [Int: SetAutofillTemplate]
    }

    private var entries: [String: Entry] = [:]

    func warm(
        exercises: [WorkoutExercise],
        formatter: DisplayUnitFormatter,
        in context: ModelContext
    ) {
        for exercise in exercises {
            refresh(exercise: exercise, formatter: formatter, in: context)
        }
    }

    func refresh(
        exercise: WorkoutExercise,
        formatter: DisplayUnitFormatter,
        in context: ModelContext
    ) {
        let mode = ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry)
        let hints = (try? LastSessionAutofill.historyHints(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            mode: mode,
            in: context,
            formatter: formatter
        )) ?? ExerciseHistoryHints(lastSessionHint: nil, previousSets: [:])

        var previousHints: [Int: String?] = [:]
        var templates: [Int: SetAutofillTemplate] = [:]
        for (setIndex, template) in hints.previousSets {
            templates[setIndex] = template
            previousHints[setIndex] = LastSessionAutofill.formatPreviousHint(
                template,
                mode: mode,
                formatter: formatter
            )
        }

        entries[key(for: exercise)] = Entry(
            lastHint: hints.lastSessionHint,
            previousHints: previousHints,
            templates: templates
        )
    }

    func lastHint(for exercise: WorkoutExercise) -> String? {
        entries[key(for: exercise)]?.lastHint
    }

    func previousHint(for exercise: WorkoutExercise, setIndex: Int) -> String? {
        entries[key(for: exercise)]?.previousHints[setIndex] ?? nil
    }

    func template(for exercise: WorkoutExercise, setIndex: Int) -> SetAutofillTemplate? {
        entries[key(for: exercise)]?.templates[setIndex]
    }

    func invalidate() {
        entries.removeAll()
    }

    private func key(for exercise: WorkoutExercise) -> String {
        let catalogName = exercise.catalogEntry?.canonicalName ?? ""
        let title = ExerciseTitleNormalizer.normalize(exercise.exerciseTitle)
        return "\(catalogName)|\(title)"
    }
}
