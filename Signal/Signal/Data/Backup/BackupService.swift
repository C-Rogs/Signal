import Foundation
import os
import SwiftData

actor BackupService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func exportJSON(exportedAt: Date = .now) async throws -> Data {
        try await MainActor.run {
            let context = ModelContext(container)
            let snapshot = try Self.buildSnapshot(from: context, exportedAt: exportedAt)
            try context.save()
            return try BackupCodec.makeEncoder().encode(snapshot)
        }
    }

    func importJSON(_ data: Data) async throws -> BackupImportResult {
        try await MainActor.run {
            let context = ModelContext(container)
            let file = try Self.decodeBackupFile(from: data)
            let before = try Self.counts(in: context)
            let result = try Self.applyImport(file, in: context)
            try context.save()
            let after = try Self.counts(in: context)
            Log.backup.info(
                "import complete sessions=\(result.importedSessionCount, privacy: .public) bodyweight=\(result.importedBodyweightCount, privacy: .public) customExercises=\(result.importedCustomExerciseCount, privacy: .public) before=\(before.summary, privacy: .public) after=\(after.summary, privacy: .public)"
            )
            return result
        }
    }

    @MainActor
    private static func buildSnapshot(from context: ModelContext, exportedAt: Date) throws -> SignalBackupFile {
        let profile = try ProfileGoalRepository.fetchProfile(in: context).map(BackupUserProfile.init)
        let bodyweight = try ProfileGoalRepository.fetchBodyweightEntries(in: context)
            .sorted { $0.date < $1.date }
            .map { BackupBodyweightEntry(date: $0.date, kg: $0.kg) }
        let goal = try ProfileGoalRepository.fetchTrainingGoal(in: context).map(BackupTrainingGoal.init)
        let sessions = try fetchAllSessions(in: context)
            .map { session in
                let id = ensureBackupID(for: session)
                return BackupWorkoutSession(session: session, id: id)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let customExercises = try fetchCustomCatalogEntries(in: context)
            .map(BackupCustomExercise.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return SignalBackupFile(
            schemaVersion: SignalBackupFile.supportedSchemaVersion,
            exportedAt: exportedAt,
            userProfile: profile,
            bodyweightLog: bodyweight,
            trainingGoal: goal,
            workoutSessions: sessions,
            customExercises: customExercises
        )
    }

    @MainActor
    private static func decodeBackupFile(from data: Data) throws -> SignalBackupFile {
        let file = try BackupCodec.makeDecoder().decode(SignalBackupFile.self, from: data)
        guard file.schemaVersion == SignalBackupFile.supportedSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(file.schemaVersion)
        }
        return file
    }

    @MainActor
    private static func applyImport(_ file: SignalBackupFile, in context: ModelContext) throws -> BackupImportResult {
        var result = BackupImportResult(
            importedSessionCount: 0,
            importedBodyweightCount: 0,
            importedCustomExerciseCount: 0
        )

        if let profilePayload = file.userProfile {
            try importUserProfile(profilePayload, in: context)
        }
        if let goalPayload = file.trainingGoal {
            try importTrainingGoal(goalPayload, in: context)
        }

        var knownBodyweight = try ProfileGoalRepository.fetchBodyweightEntries(in: context)
        for entry in file.bodyweightLog {
            guard !knownBodyweight.contains(where: { Self.matchesBodyweight($0, entry) }) else { continue }
            let added = try ProfileGoalRepository.appendBodyweight(
                kg: entry.kg,
                date: entry.date,
                in: context,
                save: false
            )
            knownBodyweight.append(added)
            result.importedBodyweightCount += 1
        }

        let existingSessionIDs = Set(try fetchAllSessions(in: context).compactMap(\.backupID))
        for sessionPayload in file.workoutSessions {
            guard !existingSessionIDs.contains(sessionPayload.id) else { continue }
            try insertSession(sessionPayload, in: context)
            result.importedSessionCount += 1
        }

        let existingCustomNames = Set(
            try fetchCustomCatalogEntries(in: context).map(\.canonicalName)
        )
        for exercisePayload in file.customExercises {
            guard !existingCustomNames.contains(exercisePayload.name) else { continue }
            try insertCustomExercise(exercisePayload, in: context)
            result.importedCustomExerciseCount += 1
        }

        return result
    }

    @MainActor
    private static func importUserProfile(_ payload: BackupUserProfile, in context: ModelContext) throws {
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        if profile.heightCm == nil { profile.heightCm = payload.heightCm }
        if profile.bodyweightKg == nil { profile.bodyweightKg = payload.bodyweightKg }
        if profile.dateOfBirth == nil { profile.dateOfBirth = payload.dateOfBirth }
        if profile.biologicalSex == nil { profile.biologicalSex = payload.biologicalSex }
    }

    @MainActor
    private static func importTrainingGoal(_ payload: BackupTrainingGoal, in context: ModelContext) throws {
        if let existing = try ProfileGoalRepository.fetchTrainingGoal(in: context) {
            if existing.notes == nil { existing.notes = payload.notes }
            return
        }
        let goal = TrainingGoal(
            goalKey: payload.goalKey,
            primaryGoal: GoalType(rawValue: payload.primaryGoalRaw) ?? .generalFitness,
            weeklyTrainingDays: payload.weeklyTrainingDays,
            targetRIR: payload.targetRIR,
            updatedAt: payload.updatedAt,
            notes: payload.notes
        )
        context.insert(goal)
    }

    @MainActor
    private static func insertSession(_ payload: BackupWorkoutSession, in context: ModelContext) throws {
        let session = WorkoutSession(
            title: payload.title,
            sessionDescription: payload.sessionDescription,
            startTime: payload.startedAt,
            endTime: payload.finishedAt,
            date: payload.date,
            source: payload.source,
            healthKitWorkoutUUID: payload.healthKitWorkoutUUID,
            healthKitEffortSampleUUID: payload.healthKitEffortSampleUUID
        )
        session.backupID = payload.id
        context.insert(session)

        for exercisePayload in payload.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise = WorkoutExercise(
                exerciseTitle: exercisePayload.name,
                notes: exercisePayload.notes,
                supersetId: exercisePayload.supersetId,
                order: exercisePayload.order,
                catalogMatchFlag: exercisePayload.catalogMatchFlag,
                restDurationSeconds: exercisePayload.restDurationSeconds,
                autoStartRestOnSetComplete: exercisePayload.autoStartRestOnSetComplete,
                restTimerEndsAt: exercisePayload.restTimerEndsAt
            )
            exercise.session = session
            session.exercises.append(exercise)

            for setPayload in exercisePayload.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
                let setEntry = SetEntry(
                    setIndex: setPayload.setIndex,
                    setType: setPayload.setType,
                    weightKg: setPayload.weightKg,
                    reps: setPayload.reps,
                    distanceKm: setPayload.distanceKm,
                    durationSeconds: setPayload.durationSeconds,
                    rpe: setPayload.rpe,
                    isCompleted: setPayload.isCompleted,
                    hasBeenEdited: setPayload.hasBeenEdited,
                    startedAt: setPayload.startedAt,
                    completedAt: setPayload.completedAt
                )
                setEntry.exercise = exercise
                exercise.sets.append(setEntry)
            }
        }
    }

    @MainActor
    private static func insertCustomExercise(_ payload: BackupCustomExercise, in context: ModelContext) throws {
        let primaryMuscles = payload.primaryMuscleRawValues.compactMap(Muscle.init(rawValue:))
        let secondaryMuscles = payload.secondaryMuscleRawValues.compactMap(Muscle.init(rawValue:))
        let entry = ExerciseCatalog(
            canonicalName: payload.name,
            aliases: payload.aliases,
            primaryMuscles: primaryMuscles.isEmpty ? [.chest] : primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            movementPattern: MovementPattern(rawValue: payload.movementPatternRaw) ?? .isolation,
            equipment: ExerciseEquipment(rawValue: payload.equipmentRaw) ?? .other,
            isUnilateral: payload.isUnilateral,
            isCustom: true
        )
        context.insert(entry)
    }

    @MainActor
    private static func fetchAllSessions(in context: ModelContext) throws -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    private static func fetchCustomCatalogEntries(in context: ModelContext) throws -> [ExerciseCatalog] {
        let descriptor = FetchDescriptor<ExerciseCatalog>(
            predicate: #Predicate { $0.isCustom == true },
            sortBy: [SortDescriptor(\.canonicalName, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    private static func ensureBackupID(for session: WorkoutSession) -> UUID {
        if let backupID = session.backupID {
            return backupID
        }
        let id = UUID()
        session.backupID = id
        return id
    }

    @MainActor
    private static func matchesBodyweight(_ existing: BodyweightEntry, _ incoming: BackupBodyweightEntry) -> Bool {
        Calendar.current.isDate(existing.date, inSameDayAs: incoming.date)
            && abs(existing.kg - incoming.kg) < 0.001
    }

    @MainActor
    private static func counts(in context: ModelContext) throws -> BackupStoreCounts {
        let sessions = try fetchAllSessions(in: context).count
        let bodyweight = try ProfileGoalRepository.fetchBodyweightEntries(in: context).count
        let customExercises = try fetchCustomCatalogEntries(in: context).count
        return BackupStoreCounts(sessions: sessions, bodyweight: bodyweight, customExercises: customExercises)
    }
}

private struct BackupStoreCounts {
    var sessions: Int
    var bodyweight: Int
    var customExercises: Int

    var summary: String {
        "sessions=\(sessions) bodyweight=\(bodyweight) customExercises=\(customExercises)"
    }
}

@MainActor
private extension BackupUserProfile {
    init(profile: UserProfile) {
        profileKey = profile.profileKey
        heightCm = profile.heightCm
        bodyweightKg = profile.bodyweightKg
        dateOfBirth = profile.dateOfBirth
        biologicalSex = profile.biologicalSex
    }
}

@MainActor
private extension BackupTrainingGoal {
    init(goal: TrainingGoal) {
        goalKey = goal.goalKey
        primaryGoalRaw = goal.primaryGoalRaw
        weeklyTrainingDays = goal.weeklyTrainingDays
        targetRIR = goal.targetRIR
        updatedAt = goal.updatedAt
        notes = goal.notes
    }
}

@MainActor
private extension BackupWorkoutSession {
    init(session: WorkoutSession, id: UUID) {
        self.id = id
        title = session.title
        sessionDescription = session.sessionDescription
        startedAt = session.startTime
        finishedAt = session.endTime
        date = session.date
        source = session.source
        healthKitWorkoutUUID = session.healthKitWorkoutUUID
        healthKitEffortSampleUUID = session.healthKitEffortSampleUUID
        exercises = session.exercises
            .sorted { $0.order < $1.order }
            .map(BackupWorkoutExercise.init)
    }
}

@MainActor
private extension BackupWorkoutExercise {
    init(exercise: WorkoutExercise) {
        name = exercise.exerciseTitle
        notes = exercise.notes
        supersetId = exercise.supersetId
        order = exercise.order
        catalogMatchFlag = exercise.catalogMatchFlag
        restDurationSeconds = exercise.restDurationSeconds
        autoStartRestOnSetComplete = exercise.autoStartRestOnSetComplete
        restTimerEndsAt = exercise.restTimerEndsAt
        sets = exercise.sets
            .sorted { $0.setIndex < $1.setIndex }
            .map(BackupSetEntry.init)
    }
}

@MainActor
private extension BackupSetEntry {
    init(set: SetEntry) {
        setIndex = set.setIndex
        setType = set.setType
        weightKg = set.weightKg
        reps = set.reps
        distanceKm = set.distanceKm
        durationSeconds = set.durationSeconds
        rpe = set.rpe
        isCompleted = set.isCompleted
        hasBeenEdited = set.hasBeenEdited
        startedAt = set.startedAt
        completedAt = set.completedAt
    }
}

@MainActor
private extension BackupCustomExercise {
    init(entry: ExerciseCatalog) {
        name = entry.canonicalName
        aliases = entry.aliases
        primaryMuscleRawValues = entry.primaryMuscleRawValues
        secondaryMuscleRawValues = entry.secondaryMuscleRawValues
        movementPatternRaw = entry.movementPatternRaw
        equipmentRaw = entry.equipmentRaw
        isUnilateral = entry.isUnilateral
    }
}
