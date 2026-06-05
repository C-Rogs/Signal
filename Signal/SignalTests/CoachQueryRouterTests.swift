import XCTest
@testable import Signal

final class CoachQueryRouterTests: XCTestCase {
    func testWorkoutPrescriptionRoute() {
        XCTAssertEqual(CoachQueryRouter.classify("What should I train today?"), .workoutPrescription)
        XCTAssertEqual(CoachQueryRouter.classify("Give me a push day session"), .workoutPrescription)
        XCTAssertEqual(CoachQueryRouter.classify("What's my ACWR right now?"), .workoutPrescription)
        XCTAssertEqual(
            CoachQueryRouter.classify("Am I doing enough chest volume this week?"),
            .workoutPrescription
        )
    }

    func testNutritionRoute() {
        XCTAssertEqual(CoachQueryRouter.classify("Am I hitting protein?"), .nutrition)
        XCTAssertEqual(CoachQueryRouter.classify("Did I hit my protein target today?"), .nutrition)
        XCTAssertEqual(CoachQueryRouter.classify("How many calories should I eat?"), .nutrition)
    }

    func testReadinessRoute() {
        XCTAssertEqual(CoachQueryRouter.classify("Should I train legs today?"), .readiness)
        XCTAssertEqual(CoachQueryRouter.classify("How is my recovery today?"), .readiness)
        XCTAssertEqual(CoachQueryRouter.classify("How did I sleep last week?"), .readiness)
        XCTAssertEqual(CoachQueryRouter.classify("Should I deload this week?"), .readiness)
    }

    func testExerciseHistoryRoute() {
        XCTAssertEqual(
            CoachQueryRouter.classify("How has my bench press progressed?"),
            .exerciseHistory
        )
        XCTAssertEqual(CoachQueryRouter.classify("What's my squat e1RM trend?"), .exerciseHistory)
    }

    func testScheduleRoute() {
        XCTAssertEqual(CoachQueryRouter.classify("What's in my calendar tomorrow?"), .schedule)
        XCTAssertEqual(CoachQueryRouter.classify("What's on my calendar tomorrow?"), .schedule)
    }

    func testGeneralFallback() {
        XCTAssertEqual(CoachQueryRouter.classify("Hello"), .general)
    }

    func testTrainingQueryDoesNotRouteToScheduleFromTomorrowAlone() {
        XCTAssertNotEqual(CoachQueryRouter.classify("What should I train today?"), .schedule)
    }

    func testCompoundScheduleAndReadiness() {
        let classification = CoachQueryRouter.classifyDetailed(
            "Recovery and meetings both look bad tomorrow"
        )
        XCTAssertTrue(classification.isCompound)
        let scope = CoachContextScope.make(
            classification: classification,
            query: "Recovery and meetings both look bad tomorrow",
            proteinBelowTarget: false
        )
        XCTAssertTrue(scope.includePersonalReadiness)
    }

    func testNutritionScopeOmitsVolumeAndWorkouts() {
        let scope = CoachContextScope.make(
            classification: CoachClassification(route: .nutrition, topScore: 5, runnerUpRoute: nil, runnerUpScore: 0),
            query: "Am I hitting protein?",
            proteinBelowTarget: false
        )
        XCTAssertFalse(scope.metricsParts.contains(.volume))
        XCTAssertFalse(scope.metricsParts.contains(.acwr))
        XCTAssertFalse(scope.includeRecentWorkouts)
        XCTAssertTrue(scope.metricsParts.contains(.protein))
        XCTAssertEqual(scope.proteinPresentation, .fullStatus)
    }

    func testWorkoutPrescriptionScopeOmitsProteinUnlessDietMentioned() {
        let withoutDiet = CoachContextScope.make(
            classification: CoachClassification(route: .workoutPrescription, topScore: 5, runnerUpRoute: nil, runnerUpScore: 0),
            query: "What should I train today?",
            proteinBelowTarget: false
        )
        XCTAssertFalse(withoutDiet.metricsParts.contains(.protein))

        let withDeficit = CoachContextScope.make(
            classification: CoachClassification(route: .workoutPrescription, topScore: 5, runnerUpRoute: nil, runnerUpScore: 0),
            query: "What should I train today?",
            proteinBelowTarget: true
        )
        XCTAssertTrue(withDeficit.metricsParts.contains(.protein))
    }

    func testReadinessScopeLimitsWorkoutHistory() {
        let scope = CoachContextScope.make(
            classification: CoachClassification(route: .readiness, topScore: 5, runnerUpRoute: nil, runnerUpScore: 0),
            query: "Should I push hard?",
            proteinBelowTarget: false
        )
        XCTAssertEqual(scope.recentWorkoutLimit, 1)
        XCTAssertFalse(scope.metricsParts.contains(.volume))
    }
}
