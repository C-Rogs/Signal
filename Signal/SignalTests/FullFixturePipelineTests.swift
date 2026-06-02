import Foundation
import SwiftData
import Testing
@testable import Signal

/// End-to-end import mirroring Import tab: Apple Health XML, then Hevy CSV, then MLX embed + retrieval checks.
struct FullFixturePipelineTests {
    @Test(.timeLimit(.minutes(90)))
    func fullImportPipelineHealthThenHevyWithMLVerification() async throws {
        let healthURL = try #require(FixturePaths.healthExportXML)
        let hevyURL = try #require(FixturePaths.hevyCSV)

        if ProcessInfo.processInfo.environment["SIGNAL_USE_NL_EMBEDDING"] == "1" {
            EmbeddingBackend.useNLContextualEmbeddingFallback = true
        }

        let container = try SignalModelContainer.make(inMemoryOnly: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let pipelineStarted = Date()
        print("[FIXTURE-PIPELINE] health file=\(healthURL.path)")
        print("[FIXTURE-PIPELINE] hevy file=\(hevyURL.path)")

        let healthResult = try await AppleHealthXMLImporter.run(
            fileURL: healthURL,
            modelContainer: container,
            calendar: calendar,
            onProgress: { update in
                if update.phase == .embedding, update.vectorsWritten > 0, update.vectorsWritten % 50 == 0 {
                    print("[FIXTURE-PIPELINE] health embedding vectors=\(update.vectorsWritten)")
                }
            }
        )

        #expect(healthResult.cancelled == false)
        #expect(healthResult.sanityWarning == nil, "sanity: \(healthResult.sanityWarning ?? "")")
        #expect(healthResult.recordsScanned > 10_000)
        #expect(healthResult.tier1RecordsKept > 1_000)
        #expect(healthResult.dailyMetricCount >= 100)
        #expect(healthResult.healthVectorCount >= 100)
        #expect(healthResult.healthVectorCount >= healthResult.dailyMetricCount)

        let appleWorkoutsAfterHealth = try await MainActor.run {
            let context = ModelContext(container)
            return try AppleWorkoutStore.count(in: context)
        }
        #expect(appleWorkoutsAfterHealth > 0)

        print(
            """
            [FIXTURE-PIPELINE] health done scanned=\(healthResult.recordsScanned) \
            tier1=\(healthResult.tier1RecordsKept) metrics=\(healthResult.dailyMetricCount) \
            vectors=\(healthResult.healthVectorCount) appleWorkouts=\(appleWorkoutsAfterHealth)
            """
        )

        let hevyResult = try await HevyCSVImporter.run(
            fileURL: hevyURL,
            modelContainer: container,
            calendar: calendar,
            onProgress: { update in
                if update.phase == .embedding, update.vectorsUpdated > 0, update.vectorsUpdated % 20 == 0 {
                    print("[FIXTURE-PIPELINE] hevy embedding vectors=\(update.vectorsUpdated)")
                }
            }
        )

        #expect(hevyResult.cancelled == false)
        #expect(hevyResult.rowsParsed > 100)
        #expect(hevyResult.sessionsBuilt > 10)
        #expect(hevyResult.setsPersisted > 100)
        #expect(hevyResult.vectorsUpdatedThisRun > 0)

        let storeBundle = try await MainActor.run { () throws -> (SwiftDataVectorStore, Int, Int) in
            let context = ModelContext(container)
            let store = SwiftDataVectorStore(context: context)
            let vectors = try store.count()
            let metrics = try DailyMetricStore.count(in: context)
            let hevyTotals = try WorkoutStore.counts(source: HevyCSVImporter.importSource, in: context)
            print(
                """
                [FIXTURE-PIPELINE] hevy done sessions=\(hevyTotals.sessionCount) \
                sets=\(hevyTotals.setCount) vectors=\(vectors) metrics=\(metrics)
                """
            )
            return (store, vectors, metrics)
        }

        let store = storeBundle.0
        #expect(storeBundle.1 >= healthResult.dailyMetricCount)
        #expect(storeBundle.1 > 0)

        let service = EmbeddingBackend.makeService()
        try await Self.verifyVectorDimensions(container: container, expectedDimension: service.outputDimension)
        try await Self.verifySemanticRetrieval(store: store, service: service)

        let elapsed = Date().timeIntervalSince(pipelineStarted)
        print("[FIXTURE-PIPELINE] complete elapsedSec=\(String(format: "%.1f", elapsed))")
    }

    private static func verifyVectorDimensions(
        container: ModelContainer,
        expectedDimension: Int
    ) async throws {
        let rows = try await MainActor.run {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<HealthVector>())
        }
        #expect(!rows.isEmpty)
        for row in rows.prefix(20) {
            #expect(row.vector.count == expectedDimension)
            #expect(!row.vector.contains { $0.isNaN })
        }
        print("[FIXTURE-PIPELINE] ML check dimensions ok sample=\(min(20, rows.count)) dim=\(expectedDimension)")
    }

    private static func verifySemanticRetrieval(
        store: SwiftDataVectorStore,
        service: any EmbeddingService
    ) async throws {
        if let gemma = service as? GemmaEmbeddingService {
            _ = try await gemma.ensureLoaded()
        }

        let sleepNeighbors = try await EmbeddingVectorStoreBridge.search(
            query: "how was my sleep last night recovery rest",
            store: store,
            service: service,
            k: 8
        )
        #expect(!sleepNeighbors.isEmpty)
        let sleepHits = sleepNeighbors.filter {
            $0.summaryText.localizedCaseInsensitiveContains("sleep")
                || $0.summaryText.localizedCaseInsensitiveContains("hrv")
        }
        #expect(sleepHits.count >= 1, "top sleep query should hit sleep/HRV summaries")
        print(
            "[FIXTURE-PIPELINE] ML sleep query top=\(sleepNeighbors[0].summaryText.prefix(120))... sim=\(sleepNeighbors[0].similarity)"
        )

        let workoutNeighbors = try await EmbeddingVectorStoreBridge.search(
            query: "heavy leg day squat deadlift training session",
            store: store,
            service: service,
            k: 8
        )
        #expect(!workoutNeighbors.isEmpty)
        let workoutHits = workoutNeighbors.filter {
            $0.summaryText.localizedCaseInsensitiveContains("workout")
                || $0.summaryText.localizedCaseInsensitiveContains("squat")
                || $0.summaryText.localizedCaseInsensitiveContains("deadlift")
                || $0.summaryText.localizedCaseInsensitiveContains(" @ ")
        }
        #expect(workoutHits.count >= 1, "top workout query should hit Hevy or activity summaries")
        print(
            "[FIXTURE-PIPELINE] ML workout query top=\(workoutNeighbors[0].summaryText.prefix(120))... sim=\(workoutNeighbors[0].similarity)"
        )

        let sleepScore = sleepNeighbors.first?.similarity ?? 0
        let workoutScore = workoutNeighbors.first?.similarity ?? 0
        print(
            "[FIXTURE-PIPELINE] ML top similarities sleep=\(sleepScore) workout=\(workoutScore)"
        )
    }
}
