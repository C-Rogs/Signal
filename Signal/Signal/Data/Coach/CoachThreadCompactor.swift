import Foundation
import FoundationModels
import os

enum CoachThreadCompactor {
    private nonisolated static let summaryInstructions = """
        Summarize this coaching conversation in 200 words or fewer.
        Preserve: agreed workout plan, time or injury constraints, open questions, and key numbers cited.
        Write in third person about the athlete. No bullet lists unless essential.
        """

    static func summarizeConversation(_ conversation: String) async throws -> String {
        let trimmed = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No prior conversation to summarize."
        }

        let session = LanguageModelSession(instructions: summaryInstructions)
        guard !session.isResponding else {
            throw CoachError.busy
        }

        let stream = session.streamResponse(
            to: "Summarize this thread:\n\n\(trimmed)"
        )
        var combined = ""
        for try await snapshot in stream {
            combined = snapshot.content
        }
        let summary = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw CoachError.compactionFailed
        }
        Log.coach.info("coach compact summaryChars=\(summary.count, privacy: .public)")
        return summary
    }

    nonisolated static func trimmedMessages(
        summary: String,
        from messages: [ChatMessage]
    ) -> [ChatMessage] {
        var result: [ChatMessage] = [
            ChatMessage(
                role: .assistant,
                text: "### Conversation summary\n\(summary)",
                isCompactSummary: true
            ),
        ]

        let dialogue = messages.filter { !$0.isCompactSummary }
        if dialogue.count >= 2 {
            result.append(contentsOf: dialogue.suffix(2))
        } else {
            result.append(contentsOf: dialogue)
        }
        return result
    }
}
