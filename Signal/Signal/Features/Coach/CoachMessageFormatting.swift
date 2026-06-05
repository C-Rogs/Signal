import Foundation
import SwiftUI
import UIKit

enum CoachMessageFormatting {
    nonisolated static func attributedMarkdown(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full

        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return plainFallback(text)
        }

        applyCoachStyling(to: &parsed)
        return parsed
    }

    nonisolated static func plainStreamingText(_ text: String) -> String {
        text
    }

    private nonisolated static func plainFallback(_ text: String) -> AttributedString {
        var inlineOptions = AttributedString.MarkdownParsingOptions()
        inlineOptions.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let inline = try? AttributedString(markdown: text, options: inlineOptions) {
            var styled = inline
            applyCoachStyling(to: &styled)
            return styled
        }
        return AttributedString(text)
    }

    private nonisolated static func applyParagraphStyle(
        to container: inout AttributeContainer,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat
    ) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        container[AttributeScopes.UIKitAttributes.ParagraphStyleAttribute.self] = style
    }

    private nonisolated static func applyCoachStyling(to attributed: inout AttributedString) {
        let bodyFont = Font.body
        let codeBackground = UIColor(named: "SurfaceElevated") ?? UIColor.secondarySystemFill

        for run in attributed.runs {
            var container = AttributeContainer()
            container.font = bodyFont

            if let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(level: let level):
                        container.font = headingFont(level: level)
                        applyParagraphStyle(
                            to: &container,
                            spacingBefore: level == 1 ? 0 : 10,
                            spacingAfter: 4
                        )
                    case .listItem:
                        applyParagraphStyle(to: &container, spacingBefore: 2, spacingAfter: 2)
                    case .codeBlock:
                        container.font = .system(.body, design: .monospaced)
                        container.backgroundColor = codeBackground
                        applyParagraphStyle(to: &container, spacingBefore: 6, spacingAfter: 6)
                    default:
                        break
                    }
                }
            }

            if let inlineIntent = run.inlinePresentationIntent {
                if inlineIntent.contains(.code) {
                    container.font = .system(.body, design: .monospaced)
                    container.backgroundColor = codeBackground
                }
                if inlineIntent.contains(.stronglyEmphasized) {
                    container.font = bodyFont.weight(.semibold)
                }
            }

            attributed[run.range].mergeAttributes(container)
        }
    }

    private nonisolated static func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.semibold)
        case 2:
            return .title3.weight(.semibold)
        default:
            return .headline
        }
    }
}

#if DEBUG
extension CoachMessageFormatting {
    nonisolated static func headerLevel(
        for substring: String,
        in attributed: AttributedString
    ) -> Int? {
        guard let range = attributed.range(of: substring) else { return nil }
        guard let intent = attributed[range].presentationIntent else { return nil }
        for component in intent.components {
            if case .header(level: let level) = component.kind {
                return level
            }
        }
        return nil
    }

    nonisolated static func hasStrongEmphasis(
        for substring: String,
        in attributed: AttributedString
    ) -> Bool {
        guard let range = attributed.range(of: substring) else { return false }
        let slice = attributed[range]
        return slice.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
    }

    nonisolated static func hasInlineCode(
        for substring: String,
        in attributed: AttributedString
    ) -> Bool {
        guard let range = attributed.range(of: substring) else { return false }
        return attributed[range].inlinePresentationIntent?.contains(.code) == true
    }

    nonisolated static func containsListItem(
        for substring: String,
        in attributed: AttributedString
    ) -> Bool {
        guard let range = attributed.range(of: substring) else { return false }
        guard let intent = attributed[range].presentationIntent else { return false }
        return intent.components.contains { component in
            if case .listItem = component.kind { return true }
            return false
        }
    }
}
#endif
