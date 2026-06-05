import XCTest
@testable import Signal

final class ExerciseGuideLoaderTests: XCTestCase {
    override func tearDown() {
        ExerciseGuideLoader.resetCacheForTesting()
        super.tearDown()
    }

    func testLatPulldownGuideLoadsFromBundle() {
        let steps = ExerciseGuideLoader.guide(for: "Lat Pulldown (Cable)")
        XCTAssertNotNil(steps)
        XCTAssertFalse(steps?.isEmpty ?? true)
    }

    func testUnknownExerciseReturnsNil() {
        XCTAssertNil(ExerciseGuideLoader.guide(for: "Totally Made Up Exercise XYZ"))
    }

    func testLoadedGuideCountIsPositive() {
        XCTAssertGreaterThan(ExerciseGuideLoader.loadedGuideCount(), 0)
    }
}
