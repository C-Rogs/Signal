import Foundation

enum CoachMessageFormatting {
    nonisolated static func attributedMarkdown(_ text: String) -> AttributedString {
        if let parsed = try? AttributedString(markdown: text) {
            return parsed
        }
        var inlineOptions = AttributedString.MarkdownParsingOptions()
        inlineOptions.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let inline = try? AttributedString(markdown: text, options: inlineOptions) {
            return inline
        }
        return AttributedString(text)
    }
}
