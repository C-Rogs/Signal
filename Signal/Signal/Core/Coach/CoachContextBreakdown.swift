import Foundation
import FoundationModels

enum CoachContextBreakdown {
    struct CharBuckets: Sendable, Equatable {
        var instructions = 0
        var tools = 0
        var turnOnePrompt = 0
        var conversation = 0
        var toolOutputs = 0
        var activeToolNames: [String] = []

        var total: Int {
            instructions + tools + turnOnePrompt + conversation + toolOutputs
        }
    }

    nonisolated static func charBuckets(from transcript: Transcript) -> CharBuckets {
        var buckets = CharBuckets()
        var promptCount = 0

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                buckets.instructions = segmentCharacterCount(instructions.segments)
                buckets.tools = toolDefinitionCharacterCount(instructions.toolDefinitions)
                buckets.activeToolNames = instructions.toolDefinitions.map(\.name).sorted()
            case .prompt(let prompt):
                let chars = segmentCharacterCount(prompt.segments)
                if promptCount == 0 {
                    buckets.turnOnePrompt = chars
                } else {
                    buckets.conversation += chars
                }
                promptCount += 1
            case .response(let response):
                buckets.conversation += segmentCharacterCount(response.segments)
            case .toolOutput(let output):
                buckets.toolOutputs += segmentCharacterCount(output.segments)
            case .toolCalls:
                break
            @unknown default:
                break
            }
        }

        return buckets
    }

    nonisolated static func rows(from buckets: CharBuckets, pendingPromptChars: Int = 0) -> [CoachContextBreakdownRow] {
        var rows: [CoachContextBreakdownRow] = []
        if buckets.instructions > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Instructions",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: buckets.instructions)
            ))
        }
        if buckets.tools > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Tools",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: buckets.tools)
            ))
        }
        if buckets.turnOnePrompt > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Turn 1 context",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: buckets.turnOnePrompt)
            ))
        }
        if buckets.conversation > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Conversation",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: buckets.conversation)
            ))
        }
        if buckets.toolOutputs > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Tool outputs",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: buckets.toolOutputs)
            ))
        }
        if pendingPromptChars > 0 {
            rows.append(CoachContextBreakdownRow(
                label: "Next message",
                estimatedTokens: CoachContextBudget.estimateTokens(characterCount: pendingPromptChars)
            ))
        }
        return rows
    }

    nonisolated static func activeToolNames(from transcript: Transcript) -> [String] {
        charBuckets(from: transcript).activeToolNames
    }

    nonisolated static func snapshot(
        transcript: Transcript?,
        pendingPromptChars: Int
    ) -> CoachContextUsageSnapshot {
        guard let transcript else {
            return CoachContextBudget.snapshot(
                instructionsChars: 0,
                transcriptChars: 0,
                nextPromptChars: pendingPromptChars
            )
        }

        let buckets = charBuckets(from: transcript)
        let transcriptChars = buckets.total
        let breakdown = rows(from: buckets, pendingPromptChars: pendingPromptChars)
        let totalChars = transcriptChars + pendingPromptChars

        return CoachContextBudget.snapshot(
            instructionsChars: 0,
            transcriptChars: totalChars,
            nextPromptChars: 0,
            breakdown: breakdown,
            activeToolNames: buckets.activeToolNames
        )
    }

    private nonisolated static func segmentCharacterCount(_ segments: [Transcript.Segment]) -> Int {
        segments.reduce(0) { partial, segment in
            switch segment {
            case .text(let textSegment):
                return partial + textSegment.content.count
            case .structure:
                return partial
            @unknown default:
                return partial
            }
        }
    }

    private nonisolated static func toolDefinitionCharacterCount(_ definitions: [Transcript.ToolDefinition]) -> Int {
        definitions.reduce(0) { partial, definition in
            partial + definition.name.count + definition.description.count
        }
    }
}
