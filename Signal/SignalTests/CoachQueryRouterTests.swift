import XCTest
@testable import Signal

final class CoachQueryRouterTests: XCTestCase {
    func testWorkoutPrescriptionRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("What should I train today?"),
            .workoutPrescription
        )
        XCTAssertEqual(
            CoachQueryRouter.classify("Give me a push day session"),
            .workoutPrescription
        )
    }

    func testNutritionRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("Am I hitting protein?"),
            .nutrition
        )
        XCTAssertEqual(
            CoachQueryRouter.classify("How many calories should I eat?"),
            .nutrition
        )
    }

    func testReadinessRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("Should I train legs today?"),
            .readiness
        )
        XCTAssertEqual(
            CoachQueryRouter.classify("How is my recovery and HRV?"),
            .readiness
        )
    }

    func testExerciseHistoryRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("How has my bench press progressed?"),
            .exerciseHistory
        )
        XCTAssertEqual(
            CoachQueryRouter.classify("What's my squat e1RM trend?"),
            .exerciseHistory
        )
    }

    func testScheduleRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("What's in my calendar tomorrow?"),
            .schedule
        )
    }

    func testGeneralFallback() {
        XCTAssertEqual(
            CoachQueryRouter.classify("Hello"),
            .general
        )
    }

    func testNutritionScopeOmitsVolumeAndWorkouts() {
        let scope = CoachContextScope.make(route: .nutrition, query: "Am I hitting protein?", proteinBelowTarget: false)
        XCTAssertFalse(scope.metricsParts.contains(.volume))
        XCTAssertFalse(scope.metricsParts.contains(.acwr))
        XCTAssertFalse(scope.includeRecentWorkouts)
        XCTAssertTrue(scope.metricsParts.contains(.protein))
    }

    func testWorkoutPrescriptionScopeOmitsProteinUnlessDietMentioned() {
        let withoutDiet = CoachContextScope.make(
            route: .workoutPrescription,
            query: "What should I train today?",
            proteinBelowTarget: false
        )
        XCTAssertFalse(withoutDiet.metricsParts.contains(.protein))

        let withDeficit = CoachContextScope.make(
            route: .workoutPrescription,
            query: "What should I train today?",
            proteinBelowTarget: true
        )
        XCTAssertTrue(withDeficit.metricsParts.contains(.protein))
    }

    func testReadinessScopeLimitsWorkoutHistory() {
        let scope = CoachContextScope.make(route: .readiness, query: "Should I push hard?", proteinBelowTarget: false)
        XCTAssertEqual(scope.recentWorkoutLimit, 1)
        XCTAssertFalse(scope.metricsParts.contains(.volume))
    }
}
