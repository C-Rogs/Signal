import Foundation
import SwiftData

struct RecoveryDiagnosticsSnapshot: Sendable, Equatable {
    let score: RecoveryScore
    let baselineMeanText: String
    let baselineSDText: String
    let acuteMeanText: String
    let upperBandText: String
    let lowerBandText: String
    let classificationLabel: String
    let dataPointsUsed: Int
    let hrvTermText: String
    let rhrTermText: String
    let sleepTermText: String
    let totalScoreText: String
}

enum RecoveryDiagnosticsLoader {
    @MainActor
    static func load(in context: ModelContext) -> RecoveryDiagnosticsSnapshot? {
        let descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceDay = calendar.startOfDay(for: Date())
        let metrics = rows.map(DailyMetricSnapshot.init(metric:))
        let score = RecoveryScoreCalculator.compute(
            metrics: metrics,
            referenceDay: referenceDay,
            calendar: calendar
        )

        let analysis = score.hrvAnalysis
        return RecoveryDiagnosticsSnapshot(
            score: score,
            baselineMeanText: format(analysis?.baselineMean),
            baselineSDText: format(analysis?.baselineSD),
            acuteMeanText: format(analysis?.acuteMean),
            upperBandText: format(analysis?.upperBand),
            lowerBandText: format(analysis?.lowerBand),
            classificationLabel: score.hrvClassification.rawValue,
            dataPointsUsed: analysis?.dataPointsUsed ?? 0,
            hrvTermText: formatTerm(score.breakdown.hrvTerm),
            rhrTermText: formatTerm(score.breakdown.rhrTerm),
            sleepTermText: formatTerm(score.breakdown.sleepTerm),
            totalScoreText: "\(Int(score.value.rounded()))"
        )
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func formatTerm(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value.rounded()))"
    }
}
