import Foundation

enum CoachThreadKind: Sendable, Equatable {
    case newThread
    case followUp
}

struct CoachContextBreakdownRow: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let estimatedTokens: Int

    init(label: String, estimatedTokens: Int) {
        self.id = label
        self.label = label
        self.estimatedTokens = estimatedTokens
    }
}

struct CoachContextUsageSnapshot: Sendable, Equatable {
    static let maxTokens = 4096

    let estimatedTokens: Int
    let maxTokens: Int
    let instructionsChars: Int
    let transcriptChars: Int
    let nextPromptChars: Int
    let breakdown: [CoachContextBreakdownRow]
    let activeToolNames: [String]

    var fractionUsed: Double {
        guard maxTokens > 0 else { return 0 }
        return min(1, Double(estimatedTokens) / Double(maxTokens))
    }

    var isNearLimit: Bool { fractionUsed >= 0.75 }
    var isOverLimit: Bool { fractionUsed >= 0.95 }

    static let empty = CoachContextUsageSnapshot(
        estimatedTokens: 0,
        maxTokens: maxTokens,
        instructionsChars: 0,
        transcriptChars: 0,
        nextPromptChars: 0,
        breakdown: [],
        activeToolNames: []
    )
}

struct CoachCompactResult: Sendable, Equatable {
    let summary: String
    let messages: [ChatMessage]
}
