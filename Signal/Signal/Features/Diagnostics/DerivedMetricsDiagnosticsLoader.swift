import Foundation
import SwiftData

enum DerivedMetricsDiagnosticsLoader {
    static func loadSnapshot(modelContainer: ModelContainer) async -> DerivedMetricsSnapshot {
        await DerivedMetricsService.shared.snapshot(modelContainer: modelContainer)
    }

    @MainActor
    static func loadDataQualityFlags(in context: ModelContext) -> [DataQualityFlagRow] {
        let descriptor = FetchDescriptor<DataQualityFlag>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { flag in
            DataQualityFlagRow(
                id: "\(flag.date.timeIntervalSince1970)-\(flag.metricKind)-\(flag.issue)",
                metricKind: flag.metricKind,
                dateLabel: flag.date.formatted(date: .abbreviated, time: .omitted),
                valueLabel: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), flag.originalValue),
                issue: flag.issue,
                wasCorrected: flag.wasCorrected
            )
        }
    }
}
