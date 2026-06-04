import XCTest
@testable import Signal

final class CoachMessageFormattingTests: XCTestCase {
    func testHeadingMarkdownRenders() {
        let rendered = CoachMessageFormatting.attributedMarkdown("### Tomorrow\n\nOne event at 2pm.")
        let plain = String(rendered.characters)
        XCTAssertTrue(plain.contains("Tomorrow"))
        XCTAssertTrue(plain.contains("One event at 2pm."))
    }
}
