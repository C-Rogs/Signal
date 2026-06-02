import Foundation
import Observation
import os
import SwiftData

struct SyncAnchorRow: Identifiable, Sendable, Equatable {
    let typeIdentifier: String
    let anchorByteCount: Int

    var id: String { typeIdentifier }

    var statusLabel: String {
        anchorByteCount > 0 ? "\(anchorByteCount) bytes" : "none"
    }
}

struct RAGSearchHit: Identifiable, Sendable, Equatable {
    let dayKey: String
    let summaryText: String
    let score: Float

    var id: String { "\(dayKey)-\(score)" }

    var formattedScore: String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), score)
    }
}

@MainActor
@Observable
final class DiagnosticsViewModel {
    var dailyMetricCount = 0
    var dailyMetricLatestDayKey = "none"
    var dailyMetricCountLast7Days = 0
    var dailyNutritionCount = 0
    var appleWorkoutCount = 0
    var hevyWorkoutSessionCount = 0
    var healthVectorCount = 0
    var healthVectorLatestDayKey = "none"
    var healthVectorCountLast7Days = 0
    var syncAnchorRows: [SyncAnchorRow] = []
    var queryText = ""
    var isSearching = false
    var searchResults: [RAGSearchHit] = []
    var searchError: String?
    var retrievalFootnote: String?

    private let modelContainer: ModelContainer
    private let retrievalTopK = DiagnosticsRetrieval.defaultTopK

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func refresh(healthKitManager: HealthKitManager) {
        let context = ModelContext(modelContainer)
        let calendar = Calendar.current
        let lastWeekWindow = TemporalQueryParser.window(in: "last week", calendar: calendar)
        do {
            dailyMetricCount = try context.fetchCount(FetchDescriptor<DailyMetric>())
            if let latestMetric = try context.fetch(Self.latestDailyMetricDescriptor()).first {
                dailyMetricLatestDayKey = Summarizer.dayKey(for: latestMetric.date, calendar: calendar)
            } else {
                dailyMetricLatestDayKey = "none"
            }
            if let window = lastWeekWindow {
                let rangeStart = Self.startOfDay(forDayKey: window.fromDayKey, calendar: calendar) ?? Date.distantPast
                let rangeEnd = Self.startOfDay(forDayKey: window.toDayKey, calendar: calendar) ?? Date()
                let fromDate = rangeStart
                let toDate = rangeEnd
                dailyMetricCountLast7Days = try context.fetchCount(
                    FetchDescriptor<DailyMetric>(
                        predicate: #Predicate { $0.date >= fromDate && $0.date <= toDate }
                    )
                )
            } else {
                dailyMetricCountLast7Days = 0
            }

            dailyNutritionCount = try context.fetchCount(FetchDescriptor<DailyNutrition>())
            appleWorkoutCount = try context.fetchCount(FetchDescriptor<AppleWorkout>())
            let hevySource = HevyCSVImporter.importSource
            hevyWorkoutSessionCount = try context.fetchCount(
                FetchDescriptor<WorkoutSession>(
                    predicate: #Predicate { $0.source == hevySource }
                )
            )

            healthVectorCount = try context.fetchCount(FetchDescriptor<HealthVector>())
            if let latestVector = try context.fetch(Self.latestHealthVectorDescriptor()).first {
                healthVectorLatestDayKey = latestVector.dayKey
            } else {
                healthVectorLatestDayKey = "none"
            }
            if let window = lastWeekWindow {
                let fromDayKey = window.fromDayKey
                let toDayKey = window.toDayKey
                healthVectorCountLast7Days = try context.fetchCount(
                    FetchDescriptor<HealthVector>(
                        predicate: #Predicate { $0.dayKey >= fromDayKey && $0.dayKey <= toDayKey }
                    )
                )
            } else {
                healthVectorCountLast7Days = 0
            }

            syncAnchorRows = Self.loadSyncAnchorRows(in: context)
            Log.ui.info(
                "diagnostics refreshed metrics=\(self.dailyMetricCount, privacy: .public) vectors=\(self.healthVectorCount, privacy: .public) syncFinished=\(healthKitManager.lastSyncFinishedAt != nil, privacy: .public)"
            )
        } catch {
            Log.ui.error("diagnostics refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    func runRetrievalSmokeTest() async {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchError = "Enter a query first."
            searchResults = []
            return
        }

        isSearching = true
        searchError = nil
        searchResults = []
        retrievalFootnote = nil
        defer { isSearching = false }

        let context = ModelContext(modelContainer)
        let store = SwiftDataVectorStore(context: context)
        let service = EmbeddingBackend.makeService()
        let calendar = Calendar.current
        let retrievalMode = QueryRetrievalMode.resolve(in: trimmed, calendar: calendar)

        do {
            let vectorCount = try store.count()
            guard vectorCount > 0 else {
                searchError = "No HealthVector rows yet. Import Health or Hevy data first."
                return
            }

            let temporalWindow: TemporalQueryWindow?
            let recencyIntent: Bool
            let searchPoolK: Int
            let fromDayKey: String?
            let toDayKey: String?

            switch retrievalMode {
            case .fixedWindow(let window):
                temporalWindow = window
                recencyIntent = false
                searchPoolK = retrievalTopK
                fromDayKey = window.fromDayKey
                toDayKey = window.toDayKey
            case .recencyRanking:
                temporalWindow = nil
                recencyIntent = true
                searchPoolK = vectorCount
                fromDayKey = nil
                toDayKey = nil
            case .pureCosine:
                temporalWindow = nil
                recencyIntent = false
                searchPoolK = retrievalTopK
                fromDayKey = nil
                toDayKey = nil
            }

            let rawNeighbors = try await EmbeddingVectorStoreBridge.search(
                query: trimmed,
                store: store,
                service: service,
                k: searchPoolK,
                fromDayKey: fromDayKey,
                toDayKey: toDayKey
            )

            let outcome = DiagnosticsRetrieval.rankedNeighbors(
                rawNeighbors,
                temporalWindow: temporalWindow,
                recencyIntent: recencyIntent,
                topK: retrievalTopK
            )

            if outcome.fallbackToGlobal, let label = outcome.temporalLabel {
                searchError =
                    "No indexed days in \(label) (\(temporalWindow?.fromDayKey ?? "") to \(temporalWindow?.toDayKey ?? "")). Showing global semantic matches."
            } else if let footnote = outcome.footnote {
                retrievalFootnote = footnote
            }

            searchResults = outcome.neighbors.map {
                RAGSearchHit(dayKey: $0.dayKey, summaryText: $0.summaryText, score: $0.similarity)
            }
            Log.embedding.info(
                "diagnostics RAG smoke test queryChars=\(trimmed.count, privacy: .public) hits=\(outcome.neighbors.count, privacy: .public) temporal=\(outcome.usedTemporalFilter, privacy: .public) recency=\(outcome.usedRecencyRanking, privacy: .public)"
            )
        } catch {
            Log.embedding.error(
                "diagnostics RAG smoke test failed: \(String(describing: error), privacy: .public)"
            )
            searchError = Self.describeRetrievalFailure(error)
        }
    }

    private static func latestDailyMetricDescriptor() -> FetchDescriptor<DailyMetric> {
        var descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private static func latestHealthVectorDescriptor() -> FetchDescriptor<HealthVector> {
        var descriptor = FetchDescriptor<HealthVector>(
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private static func startOfDay(forDayKey dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func loadSyncAnchorRows(in context: ModelContext) -> [SyncAnchorRow] {
        var storedByType: [String: Int] = [:]
        if let anchors = try? context.fetch(FetchDescriptor<SyncAnchor>()) {
            for anchor in anchors {
                storedByType[anchor.hkTypeIdentifier] = anchor.anchorData.count
            }
        }

        return HealthKitTier1Kind.anchoredSyncKinds.map { kind in
            let identifier = kind.anchorTypeIdentifier
            let byteCount = storedByType[identifier] ?? 0
            return SyncAnchorRow(typeIdentifier: identifier, anchorByteCount: byteCount)
        }
        .sorted { $0.typeIdentifier < $1.typeIdentifier }
    }

    private static func describeRetrievalFailure(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
