import Foundation
import Observation
import os
import SwiftData
import UIKit

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
    var uatResults: [RetrievalUATResult] = []
    var uatCorpusStats = RetrievalUATCorpusStats(
        dayCount: 0,
        earliestDayKey: "none",
        latestDayKey: "none",
        vectorCount: 0
    )
    var isRunningUAT = false
    var uatRunningTestID: String?
    var uatError: String?
    var uatReportText = ""
    var dayDumpReportText = ""
    var dayDumpError: String?
    var syncAnchorResetMessage: String?
    var derivedMetricsSnapshot = DerivedMetricsSnapshot(
        weeklyVolume: [],
        acwr: nil,
        recentE1RM: [],
        proteinTarget: nil,
        dataQualityFlagCount: 0
    )
    var dataQualityFlagRows: [DataQualityFlagRow] = []
    var isLoadingDerivedMetrics = false
    var coachQueryText = ""
    var coachResponseText = ""
    var coachContextPreview = ""
    var coachRAGPreview = ""
    var coachContextSummary = ""
    var coachModelStatusLabel = "Checking..."
    var coachModelHelpText: String?
    var coachCanAsk = true
    var coachIsBuildingContext = false
    var coachError: String?
    var coachIsResponding = false

    var uatReportCharacterCount: Int { uatReportText.count }
    var dayDumpReportCharacterCount: Int { dayDumpReportText.count }

    var canCopyDayDumpReport: Bool {
        !dayDumpReportText.isEmpty
    }

    var canCopyUATReport: Bool {
        !isRunningUAT && !uatReportText.isEmpty
    }

    private let modelContainer: ModelContainer
    private let retrievalTopK = DiagnosticsRetrieval.defaultTopK
    private let coach: FoundationModelsCoach
    private let coachContextBuilder = CoachContextBuilder()
    private var coachTask: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.coach = FoundationModelsCoach(modelContainer: modelContainer)
    }

    func prewarmCoach() {
        refreshCoachModelStatus()
        Task {
            await coach.prewarm()
        }
    }

    func refreshCoachModelStatus() {
        let status = CoachModelAvailabilityFormatter.currentStatus()
        coachModelStatusLabel = status.label
        coachCanAsk = status.canAskCoach
        coachModelHelpText = status.helpText
        Log.coach.info("coach diagnostics model status=\(status.label, privacy: .public)")
    }

    func previewCoachContext() {
        let trimmed = coachQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        coachTask?.cancel()
        coachError = nil
        coachResponseText = ""
        coachContextPreview = ""
        coachRAGPreview = ""
        coachContextSummary = ""
        coachIsBuildingContext = true

        coachTask = Task {
            do {
                let diagnostics = try await buildCoachContextDiagnostics(for: trimmed)
                try Task.checkCancellation()
                await MainActor.run {
                    applyCoachContextDiagnostics(diagnostics)
                    coachIsBuildingContext = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    coachIsBuildingContext = false
                }
            } catch {
                await MainActor.run {
                    coachIsBuildingContext = false
                    coachError = error.localizedDescription
                }
            }
        }
    }

    func askCoach() {
        let trimmed = coachQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        refreshCoachModelStatus()
        guard coachCanAsk else {
            coachError = "Foundation model is not ready. Build context to confirm RAG, then retry Ask after Apple Intelligence is available."
            return
        }

        coachTask?.cancel()
        coachError = nil
        coachResponseText = ""
        coachIsResponding = true

        coachTask = Task {
            do {
                let context = try await coachContextBuilder.buildContext(
                    for: trimmed,
                    modelContainer: modelContainer
                )
                let preview = context.assembledPrompt(query: trimmed)
                await MainActor.run {
                    applyCoachContextDiagnostics(
                        CoachContextDiagnostics(
                            ragDayCount: context.ragSummaries.count,
                            ragCharacterCount: context.ragSummaries.reduce(0) { $0 + $1.count },
                            insightCount: context.activeInsights.count,
                            recentWorkoutCount: context.recentWorkouts.count,
                            assembledPromptCharacters: preview.count,
                            ragPreview: Self.ragSectionPreview(from: context.ragSummaries),
                            fullContextPreview: preview
                        )
                    )
                }

                let stream = try await coach.respond(to: trimmed, context: context)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    await MainActor.run {
                        coachResponseText += chunk
                    }
                }
                await MainActor.run {
                    coachIsResponding = false
                    Log.coach.info("coach diagnostics response chars=\(self.coachResponseText.count, privacy: .public)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    coachIsResponding = false
                }
            } catch let error as CoachError {
                await MainActor.run {
                    coachIsResponding = false
                    coachError = Self.describeCoachError(error)
                    Log.coach.error("coach diagnostics failed: \(self.coachError ?? "", privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    coachIsResponding = false
                    coachError = error.localizedDescription
                    Log.coach.error("coach diagnostics failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
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
            dataQualityFlagRows = DerivedMetricsDiagnosticsLoader.loadDataQualityFlags(in: context)
            Log.ui.info(
                "diagnostics refreshed metrics=\(self.dailyMetricCount, privacy: .public) vectors=\(self.healthVectorCount, privacy: .public) syncFinished=\(healthKitManager.lastSyncFinishedAt != nil, privacy: .public)"
            )
        } catch {
            Log.ui.error("diagnostics refresh failed: \(String(describing: error), privacy: .public)")
        }

        Task {
            await reloadDerivedMetrics()
        }
    }

    func reloadDerivedMetrics() async {
        isLoadingDerivedMetrics = true
        defer { isLoadingDerivedMetrics = false }
        await DerivedMetricsService.shared.invalidateCache()
        let context = ModelContext(modelContainer)
        try? ExerciseProgressStore.backfillMissingRecentSessions(in: context)
        derivedMetricsSnapshot = await DerivedMetricsDiagnosticsLoader.loadSnapshot(
            modelContainer: modelContainer
        )
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

        let run = await DiagnosticsRetrievalRunner.run(
            query: trimmed,
            modelContainer: modelContainer,
            displayHitCount: retrievalTopK
        )

        if let error = run.errorMessage {
            searchError = error
            return
        }

        if run.fallbackToGlobal, let window = run.temporalWindow {
            searchError =
                "No indexed days in \(window.label) (\(window.fromDayKey) to \(window.toDayKey)). Showing global semantic matches."
        } else if let footnote = run.footnote {
            retrievalFootnote = footnote
        }

        searchResults = run.hits
        Log.embedding.info(
            "diagnostics RAG smoke test queryChars=\(trimmed.count, privacy: .public) hits=\(run.hits.count, privacy: .public) temporal=\(run.usedTemporalFilter, privacy: .public) recency=\(run.usedRecencyRanking, privacy: .public)"
        )
    }

    func runRetrievalUAT(testID: String) async {
        guard let definition = RetrievalUATCatalog.definition(id: testID) else { return }
        await runRetrievalUAT(definitions: [definition], replaceResults: false)
    }

    func runAllRetrievalUAT() async {
        await runRetrievalUAT(definitions: RetrievalUATCatalog.all, replaceResults: true)
    }

    func copyUATReportToPasteboard() {
        guard canCopyUATReport else { return }
        UIPasteboard.general.string = uatReportText
        Log.ui.info("diagnostics UAT report copied chars=\(self.uatReportText.count, privacy: .public)")
    }

    func dumpDayAndCopyToPasteboard() {
        dayDumpError = nil
        let context = ModelContext(modelContainer)
        do {
            dayDumpReportText = try DiagnosticsDayDump.buildReport(in: context)
            guard !dayDumpReportText.isEmpty else {
                dayDumpError = "Day dump report was empty."
                return
            }
            UIPasteboard.general.string = dayDumpReportText
            Log.ui.info("diagnostics day dump copied chars=\(self.dayDumpReportText.count, privacy: .public)")
        } catch {
            dayDumpReportText = ""
            dayDumpError = error.localizedDescription
            Log.ui.error("diagnostics day dump failed: \(String(describing: error), privacy: .public)")
        }
    }

    func resetSyncAnchors(healthKitManager: HealthKitManager) {
        syncAnchorResetMessage = nil
        let context = ModelContext(modelContainer)
        do {
            let removed = try SyncAnchorStore.deleteAll(in: context)
            syncAnchorRows = Self.loadSyncAnchorRows(in: context)
            syncAnchorResetMessage = "Removed \(removed) anchor(s). Run Sync now to backfill from Health."
            Log.sync.info("diagnostics sync anchors reset count=\(removed, privacy: .public)")
            healthKitManager.syncNow()
        } catch {
            syncAnchorResetMessage = error.localizedDescription
            Log.ui.error("diagnostics sync anchor reset failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func runRetrievalUAT(definitions: [RetrievalUATDefinition], replaceResults: Bool) async {
        isRunningUAT = true
        uatError = nil
        if replaceResults {
            uatResults = []
            uatReportText = ""
        }
        defer {
            isRunningUAT = false
            uatRunningTestID = nil
        }

        do {
            uatCorpusStats = try RetrievalUATGrader.corpusStats(modelContainer: modelContainer)
            let context = ModelContext(modelContainer)
            let indexes = try RetrievalUATDayIndexes.load(in: context)
            let referenceDate = Date()
            let calendar = Calendar.current

            for definition in definitions {
                uatRunningTestID = definition.id
                let run = await DiagnosticsRetrievalRunner.run(
                    query: definition.query,
                    modelContainer: modelContainer,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                let graded = RetrievalUATGrader.grade(
                    definition: definition,
                    run: run,
                    indexes: indexes,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                if let existingIndex = uatResults.firstIndex(where: { $0.definitionID == definition.id }) {
                    uatResults[existingIndex] = graded
                } else {
                    uatResults.append(graded)
                }
                Log.ui.info(
                    "diagnostics UAT \(definition.id, privacy: .public) verdict=\(graded.verdict.rawValue, privacy: .public) ratio=\(graded.ratioLabel, privacy: .public)"
                )
            }

            uatResults.sort { lhs, rhs in
                let lhsOrder = RetrievalUATCatalog.all.firstIndex { $0.id == lhs.definitionID } ?? Int.max
                let rhsOrder = RetrievalUATCatalog.all.firstIndex { $0.id == rhs.definitionID } ?? Int.max
                return lhsOrder < rhsOrder
            }
            rebuildUATReport()
        } catch {
            uatError = error.localizedDescription
            Log.ui.error("diagnostics UAT failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func rebuildUATReport() {
        guard !uatResults.isEmpty else {
            uatReportText = ""
            return
        }
        uatReportText = RetrievalUATShareReport.build(results: uatResults, corpus: uatCorpusStats)
        Log.ui.info(
            "diagnostics UAT report built chars=\(self.uatReportText.count, privacy: .public) tests=\(self.uatResults.count, privacy: .public)"
        )
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

    private static func describeCoachError(_ error: CoachError) -> String {
        switch error {
        case .busy:
            return "Coach is already responding. Wait for the current answer to finish."
        case .contextTooLarge:
            return "Context is too large for the on-device model even after trimming."
        case .rateLimited:
            return "On-device model rate limited. Try again in a moment."
        case .generationFailed(let underlying):
            if !CoachModelAvailabilityFormatter.currentStatus().canAskCoach {
                return "Foundation model is not ready. \(CoachModelAvailabilityFormatter.currentStatus().label). Retry after Apple Intelligence finishes downloading."
            }
            return underlying.localizedDescription
        }
    }

    private func buildCoachContextDiagnostics(for query: String) async throws -> CoachContextDiagnostics {
        let context = try await coachContextBuilder.buildContext(
            for: query,
            modelContainer: modelContainer
        )
        let preview = context.assembledPrompt(query: query)
        return CoachContextDiagnostics(
            ragDayCount: context.ragSummaries.count,
            ragCharacterCount: context.ragSummaries.reduce(0) { $0 + $1.count },
            insightCount: context.activeInsights.count,
            recentWorkoutCount: context.recentWorkouts.count,
            assembledPromptCharacters: preview.count,
            ragPreview: Self.ragSectionPreview(from: context.ragSummaries),
            fullContextPreview: preview
        )
    }

    private func applyCoachContextDiagnostics(_ diagnostics: CoachContextDiagnostics) {
        coachContextSummary = diagnostics.summaryLine
        coachRAGPreview = diagnostics.ragPreview
        coachContextPreview = diagnostics.fullContextPreview
        Log.coach.info("coach diagnostics context \(diagnostics.summaryLine, privacy: .public)")
    }

    private static func ragSectionPreview(from summaries: [String]) -> String {
        guard !summaries.isEmpty else { return "(no RAG days retrieved)" }
        return summaries.joined(separator: "\n\n")
    }
}
