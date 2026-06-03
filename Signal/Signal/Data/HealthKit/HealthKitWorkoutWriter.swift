import Foundation
import HealthKit
import os
import SwiftData

enum HealthKitWorkoutWriteOutcome: Sendable, Equatable {
    case saved(workoutUUID: UUID, effortSampleUUID: UUID?)
    case skippedUnavailable
    case skippedNoEffortScore
    case denied(message: String)
    case failed(message: String)
}

@MainActor
enum HealthKitWorkoutWriter {
    static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.workoutEffortScore),
    ]

    static func sync(
        sessionID: PersistentIdentifier,
        effortScore: Double?,
        modelContext: ModelContext,
        healthStore: HKHealthStore = HKHealthStore()
    ) async -> HealthKitWorkoutWriteOutcome {
        guard let session = try? modelContext.model(for: sessionID) as? WorkoutSession else {
            Log.workout.error("workout write skipped session not found")
            return .failed(message: "Saved in Signal. Could not update Apple Health.")
        }
        return await sync(
            session: session,
            effortScore: effortScore,
            modelContext: modelContext,
            healthStore: healthStore
        )
    }

    static func sync(
        session: WorkoutSession,
        effortScore: Double?,
        modelContext: ModelContext,
        healthStore: HKHealthStore = HKHealthStore()
    ) async -> HealthKitWorkoutWriteOutcome {
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.healthkit.info("workout write skipped HealthKit unavailable")
            return .skippedUnavailable
        }
        guard session.source == WorkoutSessionSource.live else {
            return .skippedUnavailable
        }
        guard let endTime = session.endTime else {
            Log.workout.warning("workout write skipped session missing endTime")
            return .failed(message: "Workout is not finished yet.")
        }

        let startTime = session.startTime
        guard endTime > startTime else {
            return .failed(message: "Workout times are invalid.")
        }

        guard let effortScore else {
            Log.workout.info("workout write skipped no effort score")
            return .skippedNoEffortScore
        }
        let score = WorkoutEffortScoreCalculator.clampAndRound(effortScore)

        if sharingAuthorizationStatus(healthStore: healthStore) == .denied {
            Log.healthkit.info("workout write denied share authorization")
            return .denied(
                message: "Saved in Signal. Enable Workouts and Effort in Settings > Health > Data Access > Signal."
            )
        }

        do {
            if let existingUUID = session.healthKitWorkoutUUID.flatMap(UUID.init(uuidString:)),
               let workout = try await fetchWorkout(uuid: existingUUID, healthStore: healthStore)
            {
                let effortUUID = try await updateEffort(
                    on: workout,
                    session: session,
                    score: score,
                    start: startTime,
                    end: endTime,
                    healthStore: healthStore
                )
                session.healthKitWorkoutUUID = workout.uuid.uuidString
                if let effortUUID {
                    session.healthKitEffortSampleUUID = effortUUID.uuidString
                }
                try modelContext.save()
                Log.workout.info(
                    "HealthKit workout updated uuid=\(workout.uuid.uuidString, privacy: .public) effort=\(score, privacy: .public)"
                )
                return .saved(workoutUUID: workout.uuid, effortSampleUUID: effortUUID)
            }

            let result = try await createWorkout(
                session: session,
                score: score,
                start: startTime,
                end: endTime,
                healthStore: healthStore
            )
            session.healthKitWorkoutUUID = result.workoutUUID.uuidString
            session.healthKitEffortSampleUUID = result.effortSampleUUID?.uuidString
            try modelContext.save()
            Log.workout.info(
                "HealthKit workout saved uuid=\(result.workoutUUID.uuidString, privacy: .public) effort=\(score, privacy: .public)"
            )
            return .saved(workoutUUID: result.workoutUUID, effortSampleUUID: result.effortSampleUUID)
        } catch {
            if HealthKitAuthorization.isAuthorizationDeniedError(error) {
                let message = "Saved in Signal. Apple Health write access is off, so Training Load was not updated."
                Log.healthkit.info("workout write denied")
                return .denied(message: message)
            }
            Log.healthkit.error("workout write failed: \(String(describing: error), privacy: .public)")
            return .failed(message: userFacingWriteFailureMessage(for: error))
        }
    }

    private enum SharingAuthorizationStatus {
        case ready
        case notDetermined
        case denied
    }

    private static func sharingAuthorizationStatus(healthStore: HKHealthStore) -> SharingAuthorizationStatus {
        let statuses = shareTypes.map { healthStore.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) {
            return .denied
        }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            return .ready
        }
        return .notDetermined
    }

    private static func userFacingWriteFailureMessage(for error: Error) -> String {
        if let writeError = error as? HealthKitWorkoutWriteError,
           writeError == .workoutUnavailableAfterFinish
        {
            return "Saved in Signal. Unlock your iPhone and try saving to Apple Health again from Train."
        }
        if let hkError = error as? HKError {
            Log.healthkit.error("workout write HKError code=\(hkError.code.rawValue, privacy: .public)")
        }
        return "Saved in Signal. Could not update Apple Health."
    }

    static func userFacingNote(for outcome: HealthKitWorkoutWriteOutcome) -> String? {
        switch outcome {
        case .denied(let message), .failed(let message):
            message
        case .saved, .skippedUnavailable, .skippedNoEffortScore:
            nil
        }
    }

    private static func createWorkout(
        session: WorkoutSession,
        score: Double,
        start: Date,
        end: Date,
        healthStore: HKHealthStore
    ) async throws -> (workoutUUID: UUID, effortSampleUUID: UUID?) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: session)
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)

        guard let workout = try await builder.finishWorkout() else {
            throw HealthKitWorkoutWriteError.workoutUnavailableAfterFinish
        }

        let effortSample = makeEffortSample(score: score, start: start, end: end)
        try await healthStore.save(effortSample)
        try await healthStore.relateWorkoutEffortSample(effortSample, with: workout, activity: nil)
        return (workout.uuid, effortSample.uuid)
    }

    private static func updateEffort(
        on workout: HKWorkout,
        session: WorkoutSession,
        score: Double,
        start: Date,
        end: Date,
        healthStore: HKHealthStore
    ) async throws -> UUID? {
        if let oldUUID = session.healthKitEffortSampleUUID.flatMap(UUID.init(uuidString:)),
           let oldSample = try await fetchSample(uuid: oldUUID, healthStore: healthStore)
        {
            try await healthStore.unrelateWorkoutEffortSample(oldSample, from: workout, activity: nil)
            try await healthStore.delete(oldSample)
        }

        let effortSample = makeEffortSample(score: score, start: start, end: end)
        try await healthStore.save(effortSample)
        try await healthStore.relateWorkoutEffortSample(effortSample, with: workout, activity: nil)
        return effortSample.uuid
    }

    private static func makeEffortSample(score: Double, start: Date, end: Date) -> HKQuantitySample {
        let effortType = HKQuantityType(.workoutEffortScore)
        let quantity = HKQuantity(unit: .appleEffortScore(), doubleValue: score)
        return HKQuantitySample(type: effortType, quantity: quantity, start: start, end: end)
    }

    private static func activityType(for session: WorkoutSession) -> HKWorkoutActivityType {
        let titles = session.exercises.map { $0.exerciseTitle.lowercased() }
        let functionalKeywords = ["clean", "snatch", "jerk", "burpee", "kettlebell", "crossfit", "functional"]
        if titles.contains(where: { title in functionalKeywords.contains(where: title.contains) }) {
            return .functionalStrengthTraining
        }
        return .traditionalStrengthTraining
    }

    private static func fetchWorkout(uuid: UUID, healthStore: HKHealthStore) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    private static func fetchSample(uuid: UUID, healthStore: HKHealthStore) async throws -> HKSample? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.workoutEffortScore),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first)
            }
            healthStore.execute(query)
        }
    }
}

private enum HealthKitWorkoutWriteError: Error, Equatable {
    case workoutUnavailableAfterFinish
}
