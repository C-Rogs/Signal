import Foundation
import FoundationModels

enum CoachTranscriptText {
    nonisolated static func fromMessages(_ messages: [ChatMessage]) -> String {
        messages
            .filter { !$0.isCompactSummary && !$0.isSystemNotice }
            .map { message in
                switch message.role {
                case .user:
                    return "User: \(message.text)"
                case .assistant:
                    return "Coach: \(message.text)"
                }
            }
            .joined(separator: "\n\n")
    }

    nonisolated static func characterCount(from messages: [ChatMessage]) -> Int {
        fromMessages(messages).count
    }

    nonisolated static func characterCount(from session: LanguageModelSession) -> Int {
        characterCount(from: session.transcript)
    }

    nonisolated static func fromSession(_ session: LanguageModelSession) -> String {
        fromTranscript(session.transcript)
    }

    nonisolated static func characterCount(from transcript: Transcript) -> Int {
        fromTranscript(transcript).count
    }

    nonisolated static func hasResponse(in transcript: Transcript) -> Bool {
        transcript.contains { entry in
            if case .response = entry { return true }
            return false
        }
    }

    nonisolated static func fromTranscript(_ transcript: Transcript) -> String {
        transcript.compactMap { line(from: $0) }.joined(separator: "\n\n")
    }

    private nonisolated static func line(from entry: Transcript.Entry) -> String? {
        switch entry {
        case .instructions(let instructions):
            let text = text(from: instructions.segments)
            guard !text.isEmpty else { return nil }
            return "Instructions: \(text)"
        case .prompt(let prompt):
            let text = text(from: prompt.segments)
            guard !text.isEmpty else { return nil }
            return "User: \(text)"
        case .response(let response):
            let text = text(from: response.segments)
            guard !text.isEmpty else { return nil }
            return "Coach: \(text)"
        case .toolCalls, .toolOutput:
            return nil
        @unknown default:
            return nil
        }
    }

    private nonisolated static func text(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            switch segment {
            case .text(let textSegment):
                return textSegment.content
            case .structure:
                return nil
            @unknown default:
                return nil
            }
        }
        .joined(separator: "\n")
    }
}
