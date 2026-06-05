import Foundation

struct FoundationModelsHealthReport: Sendable, Equatable, Codable {
    let generatedAt: Date
    let modelStatusLabel: String
    let outcomes: [FoundationModelsHealthProbeOutcome]
    let summaryLine: String

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

enum FoundationModelsHealthShareReport {
    static func build(report: FoundationModelsHealthReport) -> String {
        var lines: [String] = []
        lines.append("SIGNAL APPLE INTELLIGENCE HEALTH CHECK — \(formattedDateTime(report.generatedAt))")
        lines.append("model=\(report.modelStatusLabel)")
        lines.append("summary: \(report.summaryLine)")
        lines.append("")

        for outcome in report.outcomes {
            lines.append("[\(outcome.probeID) \(outcome.verdict.rawValue)] \(outcome.label)")
            if let detail = outcome.detail, !detail.isEmpty {
                lines.append("detail=\(detail)")
            }
            if let latency = outcome.latencyMs {
                lines.append("latencyMs=\(latency)")
            }
            if let error = outcome.errorMessage {
                lines.append("err=\(error)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
