import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct BackupServiceTests {
    private static let fixedExportDate = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func roundTripExportImportExportIsIdenticalJSON() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        try Self.seedSampleData(in: context)

        let service = BackupService(container: container)
        let firstExport = try await service.exportJSON(exportedAt: Self.fixedExportDate)
        _ = try await service.importJSON(firstExport)
        let secondExport = try await service.exportJSON(exportedAt: Self.fixedExportDate)

        #expect(firstExport == secondExport)
    }

    @Test func importIsAdditiveForExistingSessionID() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let sessionID = UUID()
        let session = WorkoutSession(
            title: "Leg Day",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: WorkoutSessionSource.live
        )
        session.backupID = sessionID
        context.insert(session)
        try context.save()

        let payload = SignalBackupFile(
            schemaVersion: SignalBackupFile.supportedSchemaVersion,
            exportedAt: Self.fixedExportDate,
            userProfile: nil,
            bodyweightLog: [],
            trainingGoal: nil,
            workoutSessions: [
                BackupWorkoutSession(
                    id: sessionID,
                    title: "Leg Day Duplicate",
                    sessionDescription: nil,
                    startedAt: session.startTime,
                    finishedAt: session.endTime,
                    date: session.date,
                    source: session.source,
                    healthKitWorkoutUUID: nil,
                    healthKitEffortSampleUUID: nil,
                    exercises: []
                ),
            ],
            customExercises: []
        )
        let data = try BackupCodec.makeEncoder().encode(payload)

        let service = BackupService(container: container)
        let result = try await service.importJSON(data)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(result.importedSessionCount == 0)
    }

    @Test func bodyweightDedupSkipsSameDateAndKg() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try ProfileGoalRepository.appendBodyweight(kg: 80, date: measuredAt, in: context)

        let payload = SignalBackupFile(
            schemaVersion: SignalBackupFile.supportedSchemaVersion,
            exportedAt: Self.fixedExportDate,
            userProfile: nil,
            bodyweightLog: [BackupBodyweightEntry(date: measuredAt, kg: 80)],
            trainingGoal: nil,
            workoutSessions: [],
            customExercises: []
        )
        let data = try BackupCodec.makeEncoder().encode(payload)

        let service = BackupService(container: container)
        let result = try await service.importJSON(data)

        let entries = try ProfileGoalRepository.fetchBodyweightEntries(in: context)
        #expect(entries.count == 1)
        #expect(result.importedBodyweightCount == 0)
    }

    @Test func schemaVersionMismatchThrowsTypedError() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let payload = SignalBackupFile(
            schemaVersion: 99,
            exportedAt: Self.fixedExportDate,
            userProfile: nil,
            bodyweightLog: [],
            trainingGoal: nil,
            workoutSessions: [],
            customExercises: []
        )
        let data = try BackupCodec.makeEncoder().encode(payload)
        let service = BackupService(container: container)

        await #expect(throws: BackupError.unsupportedSchemaVersion(99)) {
            try await service.importJSON(data)
        }
    }

    @Test func emptyStoreExportsValidJSON() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let service = BackupService(container: container)
        let data = try await service.exportJSON(exportedAt: Self.fixedExportDate)
        let decoded = try BackupCodec.makeDecoder().decode(SignalBackupFile.self, from: data)

        #expect(decoded.schemaVersion == SignalBackupFile.supportedSchemaVersion)
        #expect(decoded.userProfile == nil)
        #expect(decoded.trainingGoal == nil)
        #expect(decoded.bodyweightLog.isEmpty)
        #expect(decoded.workoutSessions.isEmpty)
        #expect(decoded.customExercises.isEmpty)
    }

    @MainActor
    private static func seedSampleData(in context: ModelContext) throws {
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        profile.heightCm = 180
        profile.bodyweightKg = 82

        let goal = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: context)
        goal.primaryGoal = .strength
        goal.weeklyTrainingDays = 4
        goal.targetRIR = 1

        _ = try ProfileGoalRepository.appendBodyweight(
            kg: 82,
            date: Date(timeIntervalSince1970: 1_699_000_000),
            in: context,
            save: false
        )

        let session = WorkoutSession(
            title: "Push",
            startTime: Date(timeIntervalSince1970: 1_700_100_000),
            endTime: Date(timeIntervalSince1970: 1_700_102_800),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: WorkoutSessionSource.live
        )
        session.backupID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        context.insert(session)

        let exercise = WorkoutExercise(exerciseTitle: "Bench Press", order: 0)
        exercise.session = session
        session.exercises.append(exercise)

        let setEntry = SetEntry(
            setIndex: 0,
            setType: "normal",
            weightKg: 100,
            reps: 5,
            rpe: 8,
            isCompleted: true,
            startedAt: Date(timeIntervalSince1970: 1_700_100_100),
            completedAt: Date(timeIntervalSince1970: 1_700_100_200)
        )
        setEntry.exercise = exercise
        exercise.sets.append(setEntry)

        let custom = ExerciseCatalog(
            canonicalName: "Custom Cable Fly",
            aliases: ["Cable fly custom"],
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .isolation,
            equipment: .cable,
            isCustom: true
        )
        context.insert(custom)
        try context.save()
    }
}
