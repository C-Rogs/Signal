import XCTest
@testable import Signal

final class CoachContextBudgetTests: XCTestCase {
    func testEstimateTokensUsesCharHeuristic() {
        let tokens = CoachContextBudget.estimateTokens(
            instructionsChars: 350,
            transcriptChars: 700,
            nextPromptChars: 350
        )
        XCTAssertEqual(tokens, 400)
    }

    func testSnapshotNearLimitAtSeventyFivePercent() {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 5400,
            transcriptChars: 5400,
            nextPromptChars: 0
        )
        XCTAssertTrue(snapshot.isNearLimit)
        XCTAssertFalse(snapshot.isOverLimit)
        XCTAssertEqual(snapshot.maxTokens, 4096)
    }

    func testSnapshotOverLimitAtNinetyFivePercent() {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 6800,
            transcriptChars: 6800,
            nextPromptChars: 22
        )
        XCTAssertTrue(snapshot.isOverLimit)
    }

    func testFractionUsedCapsAtOne() {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 20_000,
            transcriptChars: 20_000,
            nextPromptChars: 20_000
        )
        XCTAssertEqual(snapshot.fractionUsed, 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.estimatedTokens, CoachContextBudget.maxTokens)
    }

    func testRingUsesAbsoluteFractionUsed() {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 0,
            transcriptChars: 8400,
            nextPromptChars: 0
        )
        XCTAssertEqual(snapshot.fractionUsed, 2400.0 / 4096.0, accuracy: 0.01)
    }
}
