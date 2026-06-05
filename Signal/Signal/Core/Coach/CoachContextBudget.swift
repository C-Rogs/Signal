import Foundation

enum CoachContextBudget {
    nonisolated static let maxTokens = CoachContextUsageSnapshot.maxTokens
    nonisolated static let charsPerToken = 3.5

    nonisolated static func estimateTokens(characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return max(1, Int((Double(characterCount) / charsPerToken).rounded(.up)))
    }

    nonisolated static func estimateTokens(
        instructionsChars: Int,
        transcriptChars: Int,
        nextPromptChars: Int
    ) -> Int {
        estimateTokens(characterCount: instructionsChars + transcriptChars + nextPromptChars)
    }

    nonisolated static func snapshot(
        instructionsChars: Int,
        transcriptChars: Int,
        nextPromptChars: Int,
        breakdown: [CoachContextBreakdownRow] = [],
        activeToolNames: [String] = []
    ) -> CoachContextUsageSnapshot {
        let tokens = estimateTokens(
            instructionsChars: instructionsChars,
            transcriptChars: transcriptChars,
            nextPromptChars: nextPromptChars
        )
        return CoachContextUsageSnapshot(
            estimatedTokens: min(tokens, maxTokens),
            maxTokens: maxTokens,
            instructionsChars: instructionsChars,
            transcriptChars: transcriptChars,
            nextPromptChars: nextPromptChars,
            breakdown: breakdown,
            activeToolNames: activeToolNames
        )
    }
}
