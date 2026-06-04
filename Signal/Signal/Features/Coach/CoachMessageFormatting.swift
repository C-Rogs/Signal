import Foundation

enum CoachMessageFormatting {
    nonisolated static func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
