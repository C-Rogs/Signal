import Foundation

enum CoachContextBudget {
    nonisolated static let maxTokens = CoachContextUsageSnapshot.maxTokens
    nonisolated static let charsPerToken = 3.5

    nonisolated static func estimateTokens(
        instructionsChars: Int,
        transcriptChars: Int,
        nextPromptChars: Int
    ) -> Int {
        let totalChars = instructionsChars + transcriptChars + nextPromptChars
        return max(1, Int((Double(totalChars) / charsPerToken).rounded(.up)))
    }

    nonisolated static func snapshot(
        instructionsChars: Int,
        transcriptChars: Int,
        nextPromptChars: Int
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
            nextPromptChars: nextPromptChars
        )
    }
}
