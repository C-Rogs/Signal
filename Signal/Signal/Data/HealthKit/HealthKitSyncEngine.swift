import Foundation
import HealthKit
import SwiftData
import os

struct HealthKitAnchoredDelta: Sendable {
    let kind: HealthKitTier1Kind
    let addedSamples: [HKSample]
    let deletedObjectCount: Int
    let newAnchor: HKQueryAnchor?
}

struct HealthKitSyncOutcome: Sendable {
    let samplesFetchedByType: [String: Int]
    let deletedSamplesByType: [String: Int]
    let affectedDayCount: Int
    let metricsWritten: Int
    let vectorsWritten: Int
    let anchorsAdvanced: [String: Bool]
    let elapsedSeconds: TimeInterval
    let noOp: Bool
}

enum HealthKitSyncEngine {
    static func processDelta(
        healthStore: HKHealthStore,
        modelContainer: ModelContainer,
        calendar: Calendar,
        embeddingService: any EmbeddingService
    ) async throws -> HealthKitSyncOutcome {
        let started = Date()
        var samplesFetchedByType: [String: Int] = [:]
        var deletedSamplesByType: [String: Int] = [:]
        var anchorsAdvanced: [String: Bool] = [:]
        var affectedDays: Set<Date> = []

        let lookbackStart = lookbackStartDate(calendar: calendar)
        let syncPredicate = HKQuery.predicateForSamples(
            withStart: lookbackStart,
            end: nil,
            options: .strictStartDate
        )

        var deltas: [HealthKitAnchoredDelta] = []
        var workoutDelta: HealthKitAnchoredDelta?
        for kind in HealthKitTier1Kind.anchoredSyncKinds {
            let delta = try await fetchAnchoredDelta(
                kind: kind,
                predicate: syncPredicate,
                healthStore: healthStore,
                modelContainer: modelContainer
            )
            deltas.append(delta)
            let key = kind.anchorTypeIdentifier
            samplesFetchedByType[key] = delta.addedSamples.count
            deletedSamplesByType[key] = delta.deletedObjectCount
            anchorsAdvanced[key] = delta.newAnchor != nil

            if kind == .workout {
                workoutDelta = delta
                continue
            }

            for sample in delta.addedSamples {
                affectedDays.insert(HealthKitSampleIngestor.affectedWakeDay(for: sample, calendar: calendar))
            }
        }

        let resolvedWorkoutDelta = workoutDelta ?? HealthKitAnchoredDelta(
            kind: .workout,
            addedSamples: [],
            deletedObjectCount: 0,
            newAnchor: nil
        )

        let hadDeletions = deltas.contains { $0.deletedObjectCount > 0 }
        if hadDeletions {
            let hkDays = try await HealthKitLookbackDayIndex.dayStarts(
                healthStore: healthStore,
                calendar: calendar,
                lookbackStart: lookbackStart
            )
            affectedDays.formUnion(hkDays)
        }

        for sample in resolvedWorkoutDelta.addedSamples {
            affectedDays.insert(HealthKitSampleIngestor.affectedWakeDay(for: sample, calendar: calendar))
        }

        let workoutsWritten = try await persistWorkouts(
            from: resolvedWorkoutDelta.addedSamples,
            modelContainer: modelContainer
        )

        if affectedDays.isEmpty {
            try await persistAnchors(from: deltas, modelContainer: modelContainer)
            let elapsed = Date().timeIntervalSince(started)
            logSyncSummary(
                samplesFetchedByType: samplesFetchedByType,
                deletedSamplesByType: deletedSamplesByType,
                affectedDayCount: 0,
                metricsWritten: 0,
                vectorsWritten: 0,
                workoutsWritten: workoutsWritten,
                anchorsAdvanced: anchorsAdvanced,
                elapsedSeconds: elapsed,
                noOp: true
            )
            return HealthKitSyncOutcome(
                samplesFetchedByType: samplesFetchedByType,
                deletedSamplesByType: deletedSamplesByType,
                affectedDayCount: 0,
                metricsWritten: 0,
                vectorsWritten: 0,
                anchorsAdvanced: anchorsAdvanced,
                elapsedSeconds: elapsed,
                noOp: true
            )
        }

        let sortedDays = affectedDays.sorted()
        var metrics: [DailyMetric] = []
        var nutritionItems: [DailyNutrition] = []
        metrics.reserveCapacity(sortedDays.count)
        nutritionItems.reserveCapacity(sortedDays.count)
        for dayStart in sortedDays {
            if let metric = try await HealthKitDayAggregator.aggregate(
                dayStart: dayStart,
                healthStore: healthStore,
                calendar: calendar,
                lookbackStart: lookbackStart
            ) {
                metrics.append(metric)
            }
            if let nutrition = try await HealthKitDayAggregator.aggregateNutrition(
                dayStart: dayStart,
                healthStore: healthStore,
                calendar: calendar
            ) {
                nutritionItems.append(nutrition)
            }
        }

        let metricsWritten = try await DailyImportEmbeddingPipeline.persistMetrics(
            metrics,
            modelContainer: modelContainer
        )

        let nutritionWritten = try await MainActor.run {
            let context = ModelContext(modelContainer)
            return try DailyNutritionStore.upsertBatch(nutritionItems, in: context)
        }
        Log.sync.info("daily nutrition upserted count=\(nutritionWritten, privacy: .public)")

        let vectorsWritten = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: sortedDays,
            modelContainer: modelContainer,
            calendar: calendar,
            embeddingService: embeddingService,
            workoutSource: HevyCSVImporter.importSource,
            embedBatchSize: DailyImportEmbeddingPipeline.healthEmbedBatchSize
        ) { _ in }

        try await persistAnchors(from: deltas, modelContainer: modelContainer)

        let elapsed = Date().timeIntervalSince(started)
        logSyncSummary(
            samplesFetchedByType: samplesFetchedByType,
            deletedSamplesByType: deletedSamplesByType,
            affectedDayCount: sortedDays.count,
            metricsWritten: metricsWritten,
            vectorsWritten: vectorsWritten,
            workoutsWritten: workoutsWritten,
            anchorsAdvanced: anchorsAdvanced,
            elapsedSeconds: elapsed,
            noOp: false
        )

        return HealthKitSyncOutcome(
            samplesFetchedByType: samplesFetchedByType,
            deletedSamplesByType: deletedSamplesByType,
            affectedDayCount: sortedDays.count,
            metricsWritten: metricsWritten,
            vectorsWritten: vectorsWritten,
            anchorsAdvanced: anchorsAdvanced,
            elapsedSeconds: elapsed,
            noOp: false
        )
    }

    private static func lookbackStartDate(calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(
            byAdding: .day,
            value: -HealthKitSyncLimits.lookbackDays,
            to: today
        ) ?? today.addingTimeInterval(-Double(HealthKitSyncLimits.lookbackDays) * 86400)
    }

    private static func fetchAnchoredDelta(
        kind: HealthKitTier1Kind,
        predicate: NSPredicate,
        healthStore: HKHealthStore,
        modelContainer: ModelContainer
    ) async throws -> HealthKitAnchoredDelta {
        let anchorData = try await MainActor.run {
            let context = ModelContext(modelContainer)
            return try SyncAnchorStore.anchorData(for: kind.anchorTypeIdentifier, in: context)
        }
        let anchor: HKQueryAnchor? = anchorData.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            var query: HKAnchoredObjectQuery!
            query = HKAnchoredObjectQuery(
                type: kind.sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                healthStore.stop(query)
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    returning: HealthKitAnchoredDelta(
                        kind: kind,
                        addedSamples: samples ?? [],
                        deletedObjectCount: deleted?.count ?? 0,
                        newAnchor: newAnchor
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    @MainActor
    private static func persistWorkouts(
        from samples: [HKSample],
        modelContainer: ModelContainer
    ) throws -> Int {
        let workouts = samples.compactMap { sample -> AppleWorkout? in
            guard let hkWorkout = sample as? HKWorkout else { return nil }
            return AppleWorkoutMapper.from(hkWorkout: hkWorkout)
        }
        guard !workouts.isEmpty else { return 0 }
        let context = ModelContext(modelContainer)
        let written = try AppleWorkoutStore.upsertBatch(workouts, in: context)
        Log.sync.info("apple workouts upserted count=\(written, privacy: .public)")
        return written
    }

    @MainActor
    private static func persistAnchors(
        from deltas: [HealthKitAnchoredDelta],
        modelContainer: ModelContainer
    ) async throws {
        for delta in deltas {
            guard let anchor = delta.newAnchor else { continue }
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            let context = ModelContext(modelContainer)
            try SyncAnchorStore.upsert(
                hkTypeIdentifier: delta.kind.anchorTypeIdentifier,
                anchorData: data,
                in: context
            )
            Log.sync.info(
                "anchor advanced type=\(delta.kind.anchorTypeIdentifier, privacy: .public) bytes=\(data.count, privacy: .public)"
            )
        }
    }

    private static func logSyncSummary(
        samplesFetchedByType: [String: Int],
        deletedSamplesByType: [String: Int],
        affectedDayCount: Int,
        metricsWritten: Int,
        vectorsWritten: Int,
        workoutsWritten: Int,
        anchorsAdvanced: [String: Bool],
        elapsedSeconds: TimeInterval,
        noOp: Bool
    ) {
        let fetchedSummary = samplesFetchedByType
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let deletedSummary = deletedSamplesByType
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let anchorSummary = anchorsAdvanced
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        Log.sync.info(
            "processDelta finished noOp=\(noOp, privacy: .public) fetched {\(fetchedSummary, privacy: .public)} deleted {\(deletedSummary, privacy: .public)} daysAffected=\(affectedDayCount, privacy: .public) metricsWritten=\(metricsWritten, privacy: .public) vectorsUpdated=\(vectorsWritten, privacy: .public) workoutsWritten=\(workoutsWritten, privacy: .public) anchors {\(anchorSummary, privacy: .public)} elapsedSec=\(elapsedSeconds, format: .fixed(precision: 2), privacy: .public)"
        )
    }
}
