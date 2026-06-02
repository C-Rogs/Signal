import Foundation

struct DiagnosticsRetrievalOutcome: Sendable, Equatable {
    let neighbors: [VectorNeighbor]
    let usedTemporalFilter: Bool
    let usedRecencyRanking: Bool
    let fallbackToGlobal: Bool
    let temporalLabel: String?
    let footnote: String?
}

enum DiagnosticsRetrieval {
    static let defaultTopK = 8
    static let recencySemanticCap = 200
    static let recencyRecentLookbackDays = 90

    static func rankedNeighbors(
        _ neighbors: [VectorNeighbor],
        temporalWindow: TemporalQueryWindow?,
        recencyIntent: Bool,
        topK: Int
    ) -> DiagnosticsRetrievalOutcome {
        if let window = temporalWindow {
            let inWindow = neighbors.filter { window.contains(dayKey: $0.dayKey) }
            if !inWindow.isEmpty {
                return DiagnosticsRetrievalOutcome(
                    neighbors: Array(inWindow.prefix(topK)),
                    usedTemporalFilter: true,
                    usedRecencyRanking: false,
                    fallbackToGlobal: false,
                    temporalLabel: window.label,
                    footnote: "Filtered to \(window.label)."
                )
            }

            return DiagnosticsRetrievalOutcome(
                neighbors: [],
                usedTemporalFilter: true,
                usedRecencyRanking: false,
                fallbackToGlobal: true,
                temporalLabel: window.label,
                footnote: nil
            )
        }

        if recencyIntent {
            let recentFloor = TemporalQueryParser.dayKeyOnOrAfter(daysBack: recencyRecentLookbackDays)
            let semanticPool = Array(neighbors.prefix(recencySemanticCap))
            let recentPool = neighbors.filter { $0.dayKey >= recentFloor }

            var seenDayKeys: Set<String> = []
            var merged: [VectorNeighbor] = []
            merged.reserveCapacity(semanticPool.count + recentPool.count)
            for neighbor in semanticPool + recentPool {
                guard seenDayKeys.insert(neighbor.dayKey).inserted else { continue }
                merged.append(neighbor)
            }

            let byRecency = merged.sorted { $0.dayKey > $1.dayKey }
            return DiagnosticsRetrievalOutcome(
                neighbors: Array(byRecency.prefix(topK)),
                usedTemporalFilter: false,
                usedRecencyRanking: true,
                fallbackToGlobal: false,
                temporalLabel: nil,
                footnote: "Most recent matches"
            )
        }

        return DiagnosticsRetrievalOutcome(
            neighbors: Array(neighbors.prefix(topK)),
            usedTemporalFilter: false,
            usedRecencyRanking: false,
            fallbackToGlobal: false,
            temporalLabel: nil,
            footnote: nil
        )
    }
}
