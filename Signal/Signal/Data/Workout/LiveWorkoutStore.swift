import Foundation
import os
import SwiftData
import SwiftUI

struct SetFieldCommit: Sendable {
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var distanceKm: Double?
    var durationSeconds: Int?
    var rpe: Double?
}

struct ParsedPlanStartRequest {
    let title: String
    let exercises: [ParsedPlanExercise]

    struct ParsedPlanExercise {
        let exerciseTitle: String
        let catalogEntry: ExerciseCatalog?
        let sets: [ParsedWorkoutSet]
        let restDurationSeconds: Int?

        init(
            exerciseTitle: String,
            catalogEntry: ExerciseCatalog?,
            sets: [ParsedWorkoutSet],
            restDurationSeconds: Int? = nil
        ) {
            self.exerciseTitle = exerciseTitle
            self.catalogEntry = catalogEntry
            self.sets = sets
            self.restDurationSeconds = restDurationSeconds
        }
    }
}

@MainActor
final class LiveWorkoutStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func activeSession() throws -> WorkoutSession? {
        let source = WorkoutSessionSource.live
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.source == source && session.endTime == nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func startEmpty(title: String = "Workout") throws -> WorkoutSession {
        if let existing = try activeSession() {
            return existing
        }
        let session = WorkoutSession(
            title: title,
            startTime: .now,
            endTime: nil,
            date: Calendar.current.startOfDay(for: .now),
            source: WorkoutSessionSource.live
        )
        context.insert(session)
        try save("startEmpty")
        return session
    }

    @discardableResult
    func start(from routine: Routine) throws -> WorkoutSession {
        if let existing = try activeSession() {
            return existing
        }
        let session = WorkoutSession(
            title: routine.name,
            startTime: .now,
            endTime: nil,
            date: Calendar.current.startOfDay(for: .now),
            source: WorkoutSessionSource.live
        )
        context.insert(session)

        let templateStore = RoutineTemplateStore(context: context)
        let slots = routine.exercises.sorted { $0.order < $1.order }
        var presetSetCount = 0
        for (index, slot) in slots.enumerated() {
            let catalog = slot.catalogEntry
            let title = catalog?.canonicalName ?? slot.exerciseTitleFallback ?? "Exercise"
            let templates = slot.presetSets.isEmpty
                ? nil
                : templateStore.presetTemplates(for: slot)
            let exercise = try addExercise(
                to: session,
                catalogEntry: catalog,
                exerciseTitle: title,
                order: index,
                presetSets: templates,
                restDurationSeconds: slot.presetSets.isEmpty ? nil : slot.restDurationSeconds
            )
            if !slot.presetSets.isEmpty {
                exercise.autoStartRestOnSetComplete = slot.autoStartRestOnSetComplete
                presetSetCount += slot.presetSetCount
            }
        }
        try save("startRoutine")
        Log.workout.info(
            "started workout from routine exercises=\(slots.count, privacy: .public) presetSets=\(presetSetCount, privacy: .public) title=\(routine.name, privacy: .public)"
        )
        return session
    }

    @discardableResult
    func start(fromParsedPlan request: ParsedPlanStartRequest) throws -> WorkoutSession {
        if let existing = try activeSession() {
            return existing
        }
        let session = WorkoutSession(
            title: request.title,
            startTime: .now,
            endTime: nil,
            date: Calendar.current.startOfDay(for: .now),
            source: WorkoutSessionSource.live
        )
        context.insert(session)

        for (index, exercise) in request.exercises.enumerated() {
            let presetSets = exercise.sets.enumerated().map { offset, set in
                SetAutofillTemplate(
                    setIndex: offset,
                    setType: set.isWarmup
                        ? WorkoutSetType.warmup.storageValue
                        : WorkoutSetType.normal.storageValue,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    distanceKm: nil,
                    durationSeconds: nil,
                    rpe: set.rpe,
                    prescriptionNote: set.prescriptionNote,
                    restDurationSeconds: set.restDurationSeconds
                )
            }
            _ = try addExercise(
                to: session,
                catalogEntry: exercise.catalogEntry,
                exerciseTitle: exercise.exerciseTitle,
                order: index,
                presetSets: presetSets,
                restDurationSeconds: exercise.restDurationSeconds
            )
        }
        try save("startParsedPlan")
        Log.workout.info(
            "started workout from parsed plan exercises=\(request.exercises.count, privacy: .public) title=\(request.title, privacy: .public)"
        )
        return session
    }

    func addExercise(
        to session: WorkoutSession,
        catalogEntry: ExerciseCatalog?,
        exerciseTitle: String,
        order: Int? = nil,
        presetSets: [SetAutofillTemplate]? = nil,
        restDurationSeconds: Int? = nil
    ) throws -> WorkoutExercise {
        let nextOrder = order ?? (session.exercises.map(\.order).max() ?? -1) + 1
        let exercise = WorkoutExercise(
            exerciseTitle: exerciseTitle,
            order: nextOrder,
            catalogEntry: catalogEntry,
            restDurationSeconds: restDurationSeconds ?? 90
        )
        if catalogEntry != nil {
            let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
            let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)
            CatalogLinkService.linkExercise(exercise, catalog: catalog, aliasIndex: index)
        }
        exercise.session = session
        session.exercises.append(exercise)

        let mode = ExerciseLoggingMode.from(catalogEntry: catalogEntry)
        let templates: [SetAutofillTemplate]
        if let presetSets, !presetSets.isEmpty {
            templates = presetSets
        } else {
            templates = try LastSessionAutofill.templates(
                catalogEntry: catalogEntry,
                exerciseTitle: exerciseTitle,
                mode: mode,
                in: context
            )
        }
        for template in templates {
            let set = SetEntry(
                setIndex: template.setIndex,
                setType: template.setType,
                weightKg: template.weightKg,
                reps: template.reps,
                distanceKm: template.distanceKm,
                durationSeconds: template.durationSeconds,
                rpe: template.rpe,
                prescriptionNote: template.prescriptionNote,
                restDurationSeconds: template.restDurationSeconds,
                isCompleted: false,
                hasBeenEdited: false
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
        try save("addExercise")
        return exercise
    }

    func replaceExercise(
        _ exercise: WorkoutExercise,
        catalogEntry: ExerciseCatalog,
        exerciseTitle: String,
        recoveryScore: RecoveryScore? = nil,
        personalReadiness: PersonalReadinessProfile? = nil,
        deloadActive: Bool = false
    ) throws {
        let plan = try ExerciseSwapLoadPrescription.build(
            source: exercise,
            substitute: catalogEntry,
            recoveryScore: recoveryScore,
            personalReadiness: personalReadiness,
            deloadActive: deloadActive,
            in: context
        )
        try swapExercise(
            exercise,
            catalogEntry: catalogEntry,
            exerciseTitle: exerciseTitle,
            plan: plan
        )
    }

    func swapExercise(
        _ exercise: WorkoutExercise,
        catalogEntry: ExerciseCatalog,
        exerciseTitle: String,
        plan: SwapSetPlan
    ) throws {
        exercise.catalogEntry = catalogEntry
        exercise.exerciseTitle = exerciseTitle
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)
        CatalogLinkService.linkExercise(exercise, catalog: catalog, aliasIndex: index)

        let uncompleted = exercise.sets.filter { !$0.isCompleted }
        for set in uncompleted {
            exercise.sets.removeAll { $0.persistentModelID == set.persistentModelID }
            context.delete(set)
        }

        let baseIndex = (exercise.sets.map(\.setIndex).max() ?? -1) + 1
        for (offset, template) in plan.sets.enumerated() {
            let set = SetEntry(
                setIndex: baseIndex + offset,
                setType: template.setType,
                weightKg: template.weightKg,
                reps: template.reps,
                distanceKm: template.distanceKm,
                durationSeconds: template.durationSeconds,
                rpe: nil,
                isCompleted: false,
                hasBeenEdited: false
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
        reindexSets(in: exercise)
        try save("swapExercise")
        Log.workout.info(
            "swapped exercise to=\(exerciseTitle, privacy: .public) sets=\(plan.sets.count, privacy: .public)"
        )
    }

    func reorderExercises(in session: WorkoutSession, fromOffsets: IndexSet, toOffset: Int) throws {
        var ordered = session.exercises.sorted { $0.order < $1.order }
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (index, exercise) in ordered.enumerated() {
            exercise.order = index
        }
        try save("reorderExercises")
    }

    func removeExercise(_ exercise: WorkoutExercise, from session: WorkoutSession) throws {
        session.exercises.removeAll { $0.persistentModelID == exercise.persistentModelID }
        context.delete(exercise)
        try save("removeExercise")
    }

    func addSet(to exercise: WorkoutExercise) throws -> SetEntry {
        let nextIndex = (exercise.sets.map(\.setIndex).max() ?? -1) + 1
        let mode = ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry)
        let template = try LastSessionAutofill.templates(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            mode: mode,
            in: context
        ).last
        let set = SetEntry(
            setIndex: nextIndex,
            setType: template?.setType ?? WorkoutSetType.normal.storageValue,
            weightKg: template?.weightKg,
            reps: template?.reps,
            distanceKm: template?.distanceKm,
            durationSeconds: template?.durationSeconds,
            rpe: nil,
            isCompleted: false,
            hasBeenEdited: false
        )
        set.exercise = exercise
        exercise.sets.append(set)
        try save("addSet")
        return set
    }

    func addSuggestedWarmupSets(
        to exercise: WorkoutExercise,
        recommendation: WarmupRecommendation
    ) throws {
        let mode = ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry)
        let sorted = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        let insertCount = recommendation.setCount
        guard insertCount > 0 else { return }

        for set in sorted {
            set.setIndex += insertCount
        }

        let anchorKg = anchorWorkingWeightKg(for: exercise, sortedSets: sorted, mode: mode)

        for offset in 0..<insertCount {
            let fraction = recommendation.weightFractions[offset]
            let weightKg: Double?
            if let anchorKg, anchorKg > 0 {
                weightKg = anchorKg * fraction
            } else {
                weightKg = nil
            }
            let set = SetEntry(
                setIndex: offset,
                setType: WorkoutSetType.warmup.storageValue,
                weightKg: weightKg,
                reps: recommendation.reps,
                distanceKm: nil,
                durationSeconds: nil,
                rpe: nil,
                isCompleted: false,
                hasBeenEdited: false
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
        try save("addSuggestedWarmupSets")
    }

    private func anchorWorkingWeightKg(
        for exercise: WorkoutExercise,
        sortedSets: [SetEntry],
        mode: ExerciseLoggingMode
    ) -> Double? {
        let fromWorking = sortedSets.compactMap { set -> Double? in
            guard WorkoutSetType(storageValue: set.setType) != .warmup else { return nil }
            return set.weightKg
        }.first
        if let fromWorking { return fromWorking }
        if let any = sortedSets.compactMap(\.weightKg).first { return any }
        let templates = try? LastSessionAutofill.templates(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            mode: mode,
            in: context
        )
        return templates?.compactMap(\.weightKg).first
    }

    func deleteSet(_ set: SetEntry, from exercise: WorkoutExercise) throws {
        exercise.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        context.delete(set)
        reindexSets(in: exercise)
        try save("deleteSet")
    }

    func activateSet(_ set: SetEntry) throws {
        markSetStartedIfNeeded(set)
        try save("activateSet")
    }

    func commitSetFields(_ set: SetEntry, fields: SetFieldCommit) throws {
        markSetStartedIfNeeded(set)
        set.setType = fields.setType
        if let weightKg = fields.weightKg, weightKg == 0 {
            set.weightKg = nil
        } else {
            set.weightKg = fields.weightKg
        }
        set.reps = fields.reps
        set.distanceKm = fields.distanceKm
        set.durationSeconds = fields.durationSeconds
        set.rpe = fields.rpe
        set.hasBeenEdited = true
        try save("commitSetFields")
    }

    func toggleSetComplete(_ set: SetEntry, exercise: WorkoutExercise, completed: Bool) throws {
        markSetStartedIfNeeded(set)
        set.isCompleted = completed
        set.hasBeenEdited = true
        if completed {
            let now = Date.now
            set.completedAt = now
            startNextSetAfterCompleting(set, in: exercise, at: now)
            if exercise.autoStartRestOnSetComplete {
                let restSeconds = set.restDurationSeconds ?? exercise.restDurationSeconds
                exercise.restTimerEndsAt = now.addingTimeInterval(TimeInterval(restSeconds))
            }
        } else {
            set.completedAt = nil
        }
        try save("toggleSetComplete")
    }

    func startRestTimer(for exercise: WorkoutExercise, durationSeconds: Int? = nil) throws {
        let duration = durationSeconds ?? exercise.restDurationSeconds
        exercise.restTimerEndsAt = Date().addingTimeInterval(TimeInterval(duration))
        try save("startRestTimer")
    }

    func adjustRestTimer(for exercise: WorkoutExercise, by seconds: Int) throws {
        if let endsAt = exercise.restTimerEndsAt {
            exercise.restTimerEndsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
        } else {
            try startRestTimer(for: exercise, durationSeconds: exercise.restDurationSeconds + seconds)
        }
        try save("adjustRestTimer")
    }

    func stopRestTimer(for exercise: WorkoutExercise) throws {
        exercise.restTimerEndsAt = nil
        try save("stopRestTimer")
    }

    func linkSuperset(_ first: WorkoutExercise, _ second: WorkoutExercise) throws {
        let id = first.supersetId ?? second.supersetId ?? UUID().uuidString
        first.supersetId = id
        second.supersetId = id
        try save("linkSuperset")
    }

    func breakSuperset(for exercise: WorkoutExercise, in session: WorkoutSession) throws {
        guard let id = exercise.supersetId else { return }
        for member in session.exercises where member.supersetId == id {
            member.supersetId = nil
        }
        try save("breakSuperset")
    }

    @discardableResult
    func finishSession(_ session: WorkoutSession) throws -> WorkoutSession {
        for exercise in session.exercises {
            exercise.restTimerEndsAt = nil
        }
        let exerciseCount = session.exercises.count
        let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }
        try context.save()
        session.endTime = .now
        session.date = Calendar.current.startOfDay(for: session.startTime)
        try save("finishSession")
        Log.workout.info(
            "finished workout exercises=\(exerciseCount, privacy: .public) sets=\(setCount, privacy: .public)"
        )
        return session
    }

    func discardSession(_ session: WorkoutSession) throws {
        context.delete(session)
        try save("discardSession")
    }

    func saveWellness(
        for session: WorkoutSession,
        energy: Int,
        mood: Int,
        stress: Int,
        sorenessByMuscleRaw: [String: Int],
        notes: String?
    ) throws -> WellnessEntry {
        let entry = WellnessEntry(
            energy: energy,
            mood: mood,
            stress: stress,
            sorenessByMuscleRaw: sorenessByMuscleRaw,
            notes: notes,
            session: session
        )
        context.insert(entry)
        try save("saveWellness")
        return entry
    }

    private func reindexSets(in exercise: WorkoutExercise) {
        let sorted = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        for (index, set) in sorted.enumerated() {
            set.setIndex = index
        }
    }

    private func markSetStartedIfNeeded(_ set: SetEntry) {
        guard set.startedAt == nil else { return }
        set.startedAt = .now
    }

    private func startNextSetAfterCompleting(_ completed: SetEntry, in exercise: WorkoutExercise, at date: Date) {
        let sorted = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        guard let index = sorted.firstIndex(where: { $0.persistentModelID == completed.persistentModelID }) else {
            return
        }
        let nextIndex = sorted.index(after: index)
        guard nextIndex < sorted.endIndex else { return }
        let next = sorted[nextIndex]
        guard next.startedAt == nil else { return }
        next.startedAt = date
    }

    private func save(_ action: String) throws {
        try context.save()
        Log.workout.debug("live workout saved action=\(action, privacy: .public)")
    }
}
