import Foundation

enum CoachUATShareReport {
    static func build(report: CoachUATReport) -> String {
        var lines: [String] = []
        lines.append("SIGNAL COACH EVALUATION — \(formattedDateTime(report.generatedAt))")
        lines.append("model=\(report.modelStatusLabel)")
        lines.append("summary: \(report.summaryLine)")
        lines.append("")

        for result in report.results {
            lines.append(contentsOf: block(for: result))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func block(for result: CoachUATResult) -> [String] {
        var lines: [String] = []
        lines.append("[\(result.definitionID) \(result.verdict.rawValue)] \"\(result.query)\"")
        lines.append("category=\(result.category.rawValue) checks=\(result.checkLabel) \(result.ratioLabel)")
        if let latency = result.latencyMs {
            lines.append("latencyMs=\(latency)")
        }
        if let error = result.errorMessage {
            lines.append("err=\(error)")
        }
        for note in result.notes {
            lines.append("note=\(note)")
        }
        lines.append("context rag=\(result.contextSnapshot.ragDayCount) insights=\(result.contextSnapshot.insightCount) promptChars=\(result.contextSnapshot.promptCharacters)")
        lines.append("response=\"\(result.responsePreview)\"")
        return lines
    }

    private static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
