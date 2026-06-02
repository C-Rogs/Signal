import Foundation

enum RetrievalUATShareReport {
    static func build(
        results: [RetrievalUATResult],
        corpus: RetrievalUATCorpusStats,
        generatedAt: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("SIGNAL ACCEPTANCE TEST — \(formattedDateTime(generatedAt))")
        if corpus.earliestDayKey == "none" {
            lines.append("corpus: \(corpus.dayCount) days none; vectors \(corpus.vectorCount)")
        } else {
            lines.append(
                "corpus: \(corpus.dayCount) days \(corpus.earliestDayKey) … \(corpus.latestDayKey); vectors \(corpus.vectorCount)"
            )
        }

        let tallies = verdictTallies(results)
        lines.append(
            "tallies PASS \(tallies.pass) FAIL \(tallies.fail) REVIEW \(tallies.review) LIMIT \(tallies.limit)"
        )
        lines.append("")

        for result in results {
            lines.append(contentsOf: block(for: result))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct VerdictTallies {
        var pass = 0
        var fail = 0
        var review = 0
        var limit = 0
    }

    private static func verdictTallies(_ results: [RetrievalUATResult]) -> VerdictTallies {
        var tallies = VerdictTallies()
        for result in results {
            switch result.verdict {
            case .pass: tallies.pass += 1
            case .fail: tallies.fail += 1
            case .review: tallies.review += 1
            case .limit: tallies.limit += 1
            }
        }
        return tallies
    }

    private static func block(for result: RetrievalUATResult) -> [String] {
        var lines: [String] = []
        lines.append("[\(result.definitionID) \(result.verdict.rawValue)] \"\(result.query)\"")
        lines.append("mode=\(result.expectedMode.rawValue) det=\(result.detectedModeLabel) check=\(result.checkLabel) \(result.ratioLabel)")
        if let error = result.errorMessage {
            lines.append("err=\(error)")
        }
        if result.hits.isEmpty {
            lines.append("hits=none")
        } else {
            for hit in result.hits.prefix(3) {
                let snippet = reportSnippet(hit.snippet)
                lines.append("\(hit.dayKey) \(hit.formattedScore) \"\(snippet)\"")
            }
        }
        if let structured = result.structuredAnswer, !structured.isEmpty {
            lines.append("structured (V2 target)=\(structured)")
        }
        return lines
    }

    private static func reportSnippet(_ text: String) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 40 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 40)
        return String(collapsed[..<end]) + "..."
    }

    private static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
