import Foundation
import HealthKit
import SwiftData
import os

struct SetHRAttributionSessionPayload: Sendable {
    let sessionID: UUID
    let title: String
    let windowStart: Date
    let windowEnd: Date
    let setsByExercise: [[SetHRAttributionSetInput]]
}

actor SetHRAttributionService {
    static let shared = SetHRAttributionService()

    private let healthStore: HKHealthStore
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cameronro.signal",
        category: "heartrate"
    )

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func attribute(sessionID: PersistentIdentifier, modelContainer: ModelContainer) async throws {
        let payload: SetHRAttributionSessionPayload? = try await MainActor.run {
            let context = ModelContext(modelContainer)
            guard let session = context.model(for: sessionID) as? WorkoutSession else { return nil }
            return try Self.buildPayload(session: session, context: context)
        }
        guard let payload else { return }

        try await ensureReadAccessIfNeeded()
        let samples = try await Self.fetchHeartRateSamples(
            healthStore: healthStore,
            start: payload.windowStart,
            end: payload.windowEnd
        )
        let points = samples.compactMap { Self.heartRatePoint(from: $0) }
        let drafts = SetHRAttributionMath.buildDraftsForSession(payload: payload, samples: points)

        try await MainActor.run {
            let context = ModelContext(modelContainer)
            try SetHeartRateDataStore.upsert(drafts, in: context)
        }

        let workRows = drafts.filter { !$0.isRestInterval }.count
        logger.info(
            "HR attribution session=\(payload.title, privacy: .public) setsAttributed=\(workRows, privacy: .public) samplesUsed=\(points.count, privacy: .public)"
        )
    }

    @MainActor
    func attribute(session: WorkoutSession, in context: ModelContext) async throws {
        try await attribute(sessionID: session.persistentModelID, modelContainer: context.container)
    }

    func attributeSessions(
        overlapping span: DateInterval,
        modelContainer: ModelContainer
    ) async {
        let sessionIDs = await MainActor.run {
            Self.sessionIDsOverlapping(span: span, modelContainer: modelContainer)
        }
        for sessionID in sessionIDs {
            do {
                try await attribute(sessionID: sessionID, modelContainer: modelContainer)
            } catch {
                logger.error(
                    "HR re-attribution failed error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func ensureReadAccessIfNeeded() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let access = await HealthKitAuthorization.resolveAccessState(healthStore: healthStore)
        guard case .notDetermined = access else { return }
        try await healthStore.requestAuthorization(
            toShare: [],
            read: HealthKitTier1Kind.authorizationReadTypes
        )
        await MainActor.run {
            HealthKitAuthorization.markReadAccessPrompted()
        }
    }

    @MainActor
    private static func buildPayload(
        session: WorkoutSession,
        context: ModelContext
    ) throws -> SetHRAttributionSessionPayload? {
        guard let windowEnd = session.endTime else { return nil }
        let sessionID = session.resolvedSessionID(in: context)
        var setsByExercise: [[SetHRAttributionSetInput]] = []
        let exercises = session.exercises.sorted { $0.order < $1.order }
        for exercise in exercises {
            let sortedSets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
            let inputs = sortedSets.map { set in
                let setType = WorkoutSetType(storageValue: set.setType)
                return SetHRAttributionSetInput(
                    entryID: set.entryID,
                    setIndex: set.setIndex,
                    isWarmup: setType == .warmup,
                    startedAt: set.startedAt,
                    completedAt: set.completedAt
                )
            }
            setsByExercise.append(inputs)
        }
        return SetHRAttributionSessionPayload(
            sessionID: sessionID,
            title: session.title,
            windowStart: session.startTime,
            windowEnd: windowEnd,
            setsByExercise: setsByExercise
        )
    }

    @MainActor
    private static func sessionIDsOverlapping(
        span: DateInterval,
        modelContainer: ModelContainer
    ) -> [PersistentIdentifier] {
        let context = ModelContext(modelContainer)
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.compactMap { session in
            guard session.startTime >= cutoff, let end = session.endTime else { return nil }
            let sessionSpan = DateInterval(start: session.startTime, end: end)
            guard sessionSpan.intersects(span) else { return nil }
            return session.persistentModelID
        }
    }

    private static func fetchHeartRateSamples(
        healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [HKQuantitySample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantitySamples = (samples ?? []).compactMap { $0 as? HKQuantitySample }
                continuation.resume(returning: quantitySamples)
            }
            DispatchQueue.global(qos: .utility).async {
                healthStore.execute(query)
            }
        }
    }

    private static func heartRatePoint(from sample: HKQuantitySample) -> HeartRateSamplePoint? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = sample.quantity.doubleValue(for: unit)
        guard bpm.isFinite, bpm > 0 else { return nil }
        return HeartRateSamplePoint(timestamp: sample.startDate, bpm: bpm)
    }
}
