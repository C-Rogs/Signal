import Foundation
import SwiftData
import os

struct HevyImportProgress: Sendable {
    var rowsParsed: Int = 0
    var sessionsBuilt: Int = 0
    var exercisesPersisted: Int = 0
    var setsPersisted: Int = 0
    var daysEnriched: Int = 0
    var vectorsUpdated: Int = 0
    var phase: Phase = .idle

    enum Phase: String, Sendable {
        case idle
        case parsing
        case persisting
        case preparingDays
        case embedding
        case finished
        case failed
        case cancelled
    }
}

struct HevyImportResult: Sendable {
    let rowsParsed: Int
    let sessionsBuilt: Int
    let exercisesPersisted: Int
    let setsPersisted: Int
    let daysEnriched: Int
    let vectorsUpdatedThisRun: Int
    let dailyMetricCount: Int
    let healthVectorCount: Int
    let elapsedSeconds: TimeInterval
    let spotCheckSummaries: [String]
    let cancelled: Bool
}

enum HevyCSVImporter {
    static let importSource = "hevy-export"

    static func run(
        fileURL: URL,
        modelContainer: ModelContainer,
        calendar: Calendar,
        onProgress: @Sendable @escaping (HevyImportProgress) -> Void
    ) async throws -> HevyImportResult {
        let started = Date()
        var progress = HevyImportProgress()
        progress.phase = .parsing
        onProgress(progress)

        let parseResult: HevyCSVParseResult
        do {
            parseResult = try HevyCSVParser.parse(fileURL: fileURL, calendar: calendar)
        } catch {
            if Task.isCancelled {
                progress.phase = .cancelled
                onProgress(progress)
                return await buildResult(
                    modelContainer: modelContainer,
                    calendar: calendar,
                    rowsParsed: 0,
                    enrichedDays: [],
                    vectorsUpdatedThisRun: 0,
                    started: started,
                    cancelled: true
                )
            }
            throw error
        }

        try Task.checkCancellation()

        progress.rowsParsed = parseResult.rowsParsed
        progress.sessionsBuilt = parseResult.sessions.count
        progress.phase = .persisting
        onProgress(progress)

        let persistCounts = try await MainActor.run {
            let context = ModelContext(modelContainer)
            try WorkoutStore.wipeLossyHevyDataIfNeeded(source: importSource, in: context)
            return try WorkoutStore.upsert(
                parsedSessions: parseResult.sessions,
                source: importSource,
                in: context
            )
        }

        progress.exercisesPersisted = persistCounts.exerciseCount
        progress.setsPersisted = persistCounts.setCount
        progress.daysEnriched = parseResult.affectedDayStarts.count
        progress.phase = .preparingDays
        onProgress(progress)

        let dayStarts = parseResult.affectedDayStarts
        try await MainActor.run {
            let context = ModelContext(modelContainer)
            for day in dayStarts {
                try DailyMetricStore.ensureDayExists(
                    date: day,
                    source: importSource,
                    in: context
                )
            }
            try context.save()
        }

        progress.phase = .embedding
        onProgress(progress)

        let embeddingService = EmbeddingBackend.makeService()
        let vectorsUpdated = try await DailyImportEmbeddingPipeline.embedAndUpsert(
            dayStarts: dayStarts,
            modelContainer: modelContainer,
            calendar: calendar,
            embeddingService: embeddingService,
            workoutSource: importSource
        ) { count in
            progress.vectorsUpdated = count
            onProgress(progress)
        }

        progress.phase = .finished
        onProgress(progress)

        let totals = await MainActor.run {
            let context = ModelContext(modelContainer)
            return (try? WorkoutStore.counts(source: importSource, in: context))
                ?? (sessionCount: 0, exerciseCount: 0, setCount: 0)
        }

        Log.import.info(
            "Hevy import complete rows=\(parseResult.rowsParsed, privacy: .public) sessions=\(totals.sessionCount, privacy: .public) exercises=\(totals.exerciseCount, privacy: .public) sets=\(totals.setCount, privacy: .public) days=\(dayStarts.count, privacy: .public) vectorsThisRun=\(vectorsUpdated, privacy: .public)"
        )

        return await buildResult(
            modelContainer: modelContainer,
            calendar: calendar,
            rowsParsed: parseResult.rowsParsed,
            enrichedDays: dayStarts,
            vectorsUpdatedThisRun: vectorsUpdated,
            started: started,
            cancelled: false
        )
    }

    @MainActor
    private static func buildResult(
        modelContainer: ModelContainer,
        calendar: Calendar,
        rowsParsed: Int,
        enrichedDays: [Date],
        vectorsUpdatedThisRun: Int,
        started: Date,
        cancelled: Bool
    ) async -> HevyImportResult {
        let context = ModelContext(modelContainer)
        let metricCount = (try? DailyMetricStore.count(in: context)) ?? 0
        let vectorCount = (try? SwiftDataVectorStore(context: context).count()) ?? 0
        let workoutCounts = (try? WorkoutStore.counts(source: importSource, in: context))
            ?? (sessionCount: 0, exerciseCount: 0, setCount: 0)

        var spotLines: [String] = []
        if let metrics = try? DailyMetricStore.fetchSpotCheckWorkoutDays(
            in: context,
            days: enrichedDays,
            calendar: calendar,
            limit: 2
        ) {
            for metric in metrics {
                let day = calendar.startOfDay(for: metric.date)
                let sessions = (try? WorkoutStore.fetchSessions(
                    for: day,
                    source: importSource,
                    in: context
                )) ?? []
                let (summary, text) = Summarizer.summarize(
                    metric: metric,
                    workoutSessions: sessions,
                    calendar: calendar
                )
                if let data = try? Summarizer.encodeJSON(summary),
                   let json = String(data: data, encoding: .utf8)
                {
                    Log.import.info("Hevy spot-check dayKey=\(summary.date, privacy: .public) json=\(json, privacy: .public)")
                    Log.import.info("Hevy spot-check dayKey=\(summary.date, privacy: .public) text=\(text, privacy: .public)")
                    spotLines.append("\(summary.date): \(text)")
                }
            }
        }

        let elapsed = Date().timeIntervalSince(started)
        Log.import.info(
            "Hevy import summary cancelled=\(cancelled, privacy: .public) metrics=\(metricCount, privacy: .public) vectors=\(vectorCount, privacy: .public) elapsedSec=\(elapsed, format: .fixed(precision: 2), privacy: .public)"
        )

        return HevyImportResult(
            rowsParsed: rowsParsed,
            sessionsBuilt: workoutCounts.sessionCount,
            exercisesPersisted: workoutCounts.exerciseCount,
            setsPersisted: workoutCounts.setCount,
            daysEnriched: enrichedDays.count,
            vectorsUpdatedThisRun: vectorsUpdatedThisRun,
            dailyMetricCount: metricCount,
            healthVectorCount: vectorCount,
            elapsedSeconds: elapsed,
            spotCheckSummaries: spotLines,
            cancelled: cancelled
        )
    }
}
