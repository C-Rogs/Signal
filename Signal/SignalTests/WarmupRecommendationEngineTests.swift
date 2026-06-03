import XCTest
@testable import Signal

final class WarmupRecommendationEngineTests: XCTestCase {
    private func input(
        enabled: Bool = true,
        mode: ExerciseLoggingMode = .strength,
        pattern: MovementPattern? = .squat,
        order: Int = 0,
        goal: GoalType = .hypertrophy,
        anchorWeightKg: Double? = 100,
        anchorReps: Int? = 8,
        alreadyHasWarmup: Bool = false
    ) -> WarmupRecommendationInput {
        WarmupRecommendationInput(
            enabled: enabled,
            mode: mode,
            movementPattern: pattern,
            exerciseOrder: order,
            goal: goal,
            anchorWeightKg: anchorWeightKg,
            anchorReps: anchorReps,
            alreadyHasWarmupSets: alreadyHasWarmup
        )
    }

    func testDisabledReturnsNil() {
        XCTAssertNil(WarmupRecommendationEngine.recommend(input(enabled: false)))
    }

    func testIsolationReturnsNil() {
        XCTAssertNil(WarmupRecommendationEngine.recommend(input(pattern: .isolation)))
    }

    func testLateOrderReturnsNil() {
        XCTAssertNil(WarmupRecommendationEngine.recommend(input(pattern: .horizontalPush, order: 5)))
    }

    func testFirstCompoundHypertrophyTwoWarmups() {
        let rec = WarmupRecommendationEngine.recommend(input())
        XCTAssertEqual(rec?.setCount, 2)
        XCTAssertEqual(rec?.weightFractions, [0.45, 0.65])
        XCTAssertEqual(rec?.reps, 8)
        XCTAssertTrue(rec?.summary.contains("2 warmup") == true)
    }

    func testSecondExercisePrimaryCompoundOneWarmup() {
        let rec = WarmupRecommendationEngine.recommend(
            input(pattern: .hinge, order: 1)
        )
        XCTAssertEqual(rec?.setCount, 1)
        XCTAssertEqual(rec?.weightFractions, [0.5])
    }

    func testAlreadyHasWarmupReturnsNil() {
        XCTAssertNil(WarmupRecommendationEngine.recommend(input(alreadyHasWarmup: true)))
    }

    func testCardioModeReturnsNil() {
        XCTAssertNil(WarmupRecommendationEngine.recommend(input(mode: .cardio)))
    }

    func testStrengthGoalFirstLiftTwoWarmupsLowerFractions() {
        let rec = WarmupRecommendationEngine.recommend(
            input(goal: .strength)
        )
        XCTAssertEqual(rec?.setCount, 2)
        XCTAssertEqual(rec?.weightFractions, [0.4, 0.6])
        XCTAssertEqual(rec?.reps, 5)
    }

    func testSummaryIncludesRoundedWeightWhenAnchorKnown() {
        let rec = WarmupRecommendationEngine.recommend(input(anchorWeightKg: 100))
        XCTAssertTrue(rec?.summary.contains("65") == true)
    }
}
