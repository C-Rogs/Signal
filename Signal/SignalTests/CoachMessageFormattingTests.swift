import XCTest
@testable import Signal

final class CoachMessageFormattingTests: XCTestCase {
    func testHeadingMarkdownRendersWithoutHashMarkers() {
        let source = "### Tomorrow\n\nOne event at 2pm."
        let rendered = CoachMessageFormatting.attributedMarkdown(source)
        let plain = String(rendered.characters)

        XCTAssertTrue(plain.contains("Tomorrow"))
        XCTAssertTrue(plain.contains("One event at 2pm."))
        XCTAssertFalse(plain.contains("###"))
        XCTAssertEqual(CoachMessageFormatting.headerLevel(for: "Tomorrow", in: rendered), 3)
    }

    func testBoldNumbersRetainEmphasis() {
        let source = "Squat e1RM is **140 kg** today."
        let rendered = CoachMessageFormatting.attributedMarkdown(source)

        XCTAssertTrue(CoachMessageFormatting.hasStrongEmphasis(for: "140 kg", in: rendered))
        XCTAssertFalse(String(rendered.characters).contains("**"))
    }

    func testBulletListRendersItems() {
        let source = """
        ### Recovery
        - Sleep: 7.2 h
        - HRV: 62 ms
        """
        let rendered = CoachMessageFormatting.attributedMarkdown(source)
        let plain = String(rendered.characters)

        XCTAssertTrue(plain.contains("Sleep: 7.2 h"))
        XCTAssertTrue(plain.contains("HRV: 62 ms"))
        XCTAssertTrue(CoachMessageFormatting.containsListItem(for: "Sleep: 7.2 h", in: rendered))
        XCTAssertTrue(CoachMessageFormatting.containsListItem(for: "HRV: 62 ms", in: rendered))
    }

    func testNumberedListRendersItems() {
        let source = "1. Warm up\n2. Working sets"
        let rendered = CoachMessageFormatting.attributedMarkdown(source)
        let plain = String(rendered.characters)

        XCTAssertTrue(plain.contains("Warm up"))
        XCTAssertTrue(plain.contains("Working sets"))
        XCTAssertTrue(CoachMessageFormatting.containsListItem(for: "Warm up", in: rendered))
    }

    func testMarkdownBlocksSplitOnBlankLinesAndHeadings() {
        let source = """
        ### Recovery
        Sleep was solid.

        ### Training
        - Squat: **140 kg**
        - Volume: 12 sets
        """
        let blocks = CoachMessageFormatting.markdownBlocks(from: source)

        XCTAssertEqual(blocks.count, 4)
        XCTAssertTrue(blocks[0].hasPrefix("### Recovery"))
        XCTAssertEqual(blocks[1], "Sleep was solid.")
        XCTAssertTrue(blocks[2].hasPrefix("### Training"))
        XCTAssertTrue(blocks[3].contains("- Squat:"))
        XCTAssertTrue(blocks[3].contains("- Volume:"))
    }

    func testCoachSampleRendersDistinctBlocks() {
        let source = """
        ### Tomorrow
        One event at 2pm.

        ### Recovery
        HRV is **62 ms**. Sleep **7.2 h**.
        """
        let blocks = CoachMessageFormatting.markdownBlocks(from: source)
        XCTAssertGreaterThanOrEqual(blocks.count, 3)

        let rendered = blocks.map { CoachMessageFormatting.attributedMarkdown($0) }
        let combined = rendered.map { String($0.characters) }.joined(separator: "\n")
        XCTAssertTrue(combined.contains("Tomorrow"))
        XCTAssertTrue(combined.contains("One event at 2pm."))
        XCTAssertTrue(combined.contains("Recovery"))
    }

    func testInlineCodeUsesMonospace() {
        let source = "Use `RPE 8` on the top set."
        let rendered = CoachMessageFormatting.attributedMarkdown(source)
        let plain = String(rendered.characters)

        XCTAssertTrue(plain.contains("RPE 8"))
        XCTAssertFalse(plain.contains("`"))
        XCTAssertTrue(CoachMessageFormatting.hasInlineCode(for: "RPE 8", in: rendered))
    }
}
