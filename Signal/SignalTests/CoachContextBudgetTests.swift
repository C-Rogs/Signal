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
            instructionsChars: 3500,
            transcriptChars: 3500,
            nextPromptChars: 700
        )
        XCTAssertTrue(snapshot.isNearLimit)
        XCTAssertFalse(snapshot.isOverLimit)
        XCTAssertEqual(snapshot.maxTokens, 4096)
    }

    func testSnapshotOverLimitAtNinetyFivePercent() {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: 7000,
            transcriptChars: 3500,
            nextPromptChars: 700
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
}
