import Foundation

enum ImportSummaryStore {
    private static let healthSummaryKey = "com.cameronro.signal.importSummary.health"
    private static let hevySummaryKey = "com.cameronro.signal.importSummary.hevy"
    private static let healthRecordedAtKey = "com.cameronro.signal.importSummary.healthAt"
    private static let hevyRecordedAtKey = "com.cameronro.signal.importSummary.hevyAt"

    static var healthSummary: String? {
        UserDefaults.standard.string(forKey: healthSummaryKey)
    }

    static var hevySummary: String? {
        UserDefaults.standard.string(forKey: hevySummaryKey)
    }

    static var healthRecordedAt: Date? {
        recordedDate(forKey: healthRecordedAtKey)
    }

    static var hevyRecordedAt: Date? {
        recordedDate(forKey: hevyRecordedAtKey)
    }

    static func recordHealth(_ result: HealthImportResult) {
        var lines = [
            "Records scanned: \(result.recordsScanned)",
            "Tier 1 kept: \(result.tier1RecordsKept)",
            "DailyMetric rows: \(result.dailyMetricCount)",
            "HealthVector rows: \(result.healthVectorCount)",
            "Elapsed: \(String(format: "%.1f", result.elapsedSeconds)) s",
        ]
        if let peak = result.peakMemoryBytes {
            lines.append("Peak memory: \(String(format: "%.1f", Double(peak) / 1_048_576)) MB")
        }
        if let warning = result.sanityWarning {
            lines.append("Warning: \(warning)")
        }
        if result.cancelled {
            lines.append("Status: cancelled")
        }
        if !result.spotCheckSummaries.isEmpty {
            lines.append("Spot-check:")
            lines.append(contentsOf: result.spotCheckSummaries)
        }
        persist(summary: lines.joined(separator: "\n"), atKey: healthSummaryKey, timeKey: healthRecordedAtKey)
    }

    static func recordHevy(_ result: HevyImportResult) {
        var lines = [
            "Rows parsed: \(result.rowsParsed)",
            "Sessions built: \(result.sessionsBuilt)",
            "Exercises persisted: \(result.exercisesPersisted)",
            "Sets persisted: \(result.setsPersisted)",
            "Days enriched: \(result.daysEnriched)",
            "Vectors updated: \(result.vectorsUpdatedThisRun)",
            "DailyMetric rows: \(result.dailyMetricCount)",
            "HealthVector rows: \(result.healthVectorCount)",
            "Elapsed: \(String(format: "%.1f", result.elapsedSeconds)) s",
        ]
        if result.cancelled {
            lines.append("Status: cancelled")
        }
        if !result.spotCheckSummaries.isEmpty {
            lines.append("Spot-check:")
            lines.append(contentsOf: result.spotCheckSummaries)
        }
        persist(summary: lines.joined(separator: "\n"), atKey: hevySummaryKey, timeKey: hevyRecordedAtKey)
    }

    private static func persist(summary: String, atKey summaryKey: String, timeKey: String) {
        UserDefaults.standard.set(summary, forKey: summaryKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timeKey)
    }

    private static func recordedDate(forKey key: String) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: key)
        guard stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }
}
