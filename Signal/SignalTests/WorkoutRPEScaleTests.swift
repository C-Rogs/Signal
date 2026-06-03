import XCTest
@testable import Signal

final class WorkoutRPEScaleTests: XCTestCase {
    func testSnapToNearestHalfStep() {
        XCTAssertEqual(WorkoutRPEScale.snapToPicker(8.2), 8)
        XCTAssertEqual(WorkoutRPEScale.snapToPicker(8.3), 8.5)
        XCTAssertEqual(WorkoutRPEScale.snapToPicker(11), 10)
        XCTAssertEqual(WorkoutRPEScale.snapToPicker(5), 6)
    }

    func testCompactLabel() {
        XCTAssertEqual(WorkoutRPEScale.compactLabel(for: 8), "8")
        XCTAssertEqual(WorkoutRPEScale.compactLabel(for: 8.5), "8.5")
    }
}
