import Foundation
import SwiftData
import Testing
@testable import Signal

struct FullHealthExportImportTests {
    @Test(.timeLimit(.minutes(75)))
    func fullAppleHealthExportImport() async throws {
        let fileURL = try #require(FixturePaths.healthExportXML)

        if ProcessInfo.processInfo.environment["SIGNAL_USE_NL_EMBEDDING"] == "1" {
            EmbeddingBackend.useNLContextualEmbeddingFallback = true
        }

        let container = try SignalModelContainer.make(inMemoryOnly: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let started = Date()
        let result = try await AppleHealthXMLImporter.run(
            fileURL: fileURL,
            modelContainer: container,
            calendar: calendar,
            onProgress: { _ in }
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.cancelled == false)
        #expect(result.sanityWarning == nil, "sanity: \(result.sanityWarning ?? "")")
        #expect(result.recordsScanned > 0)
        #expect(result.tier1RecordsKept > 0)
        #expect(result.dailyMetricCount > 0)
        #expect(result.healthVectorCount > 0)

        let workoutCount = try await MainActor.run {
            let context = ModelContext(container)
            return try AppleWorkoutStore.count(in: context)
        }
        #expect(workoutCount >= 0)

        print(
            """
            [FULL-IMPORT] file=\(fileURL.lastPathComponent) \
            scanned=\(result.recordsScanned) tier1=\(result.tier1RecordsKept) \
            metrics=\(result.dailyMetricCount) vectors=\(result.healthVectorCount) \
            workouts=\(workoutCount) elapsedSec=\(String(format: "%.1f", elapsed)) \
            peakMB=\(Double(result.peakMemoryBytes ?? 0) / 1_048_576)
            """
        )

        if !result.spotCheckSummaries.isEmpty {
            print("[FULL-IMPORT] spot-check: \(result.spotCheckSummaries.first ?? "")")
        }
    }
}
