import XCTest
@testable import Signal

@MainActor
final class TrainApplicationLifecycleTests: XCTestCase {
    override func tearDown() {
        TrainApplicationLifecycle.testingIsInTrueBackground = nil
        TrainApplicationLifecycle.isWorkoutOverlayPresented = false
        TrainApplicationLifecycle.isLiveWorkoutSetFieldEditing = false
        TrainApplicationLifecycle.isLiveWorkoutSessionInProgress = false
        TrainApplicationLifecycle.setLastDidEnterBackgroundForTesting(nil)
        super.tearDown()
    }

    func testShouldDeferForegroundHousekeepingWhenWorkoutPresentedAfterRecentBackground() {
        TrainApplicationLifecycle.setLastDidEnterBackgroundForTesting(Date())
        TrainApplicationLifecycle.isWorkoutOverlayPresented = true
        XCTAssertTrue(
            TrainApplicationLifecycle.shouldDeferForegroundHousekeeping(workoutPresented: false)
        )
    }

    func testShouldDeferForegroundHousekeepingWhileEditing() {
        TrainApplicationLifecycle.isWorkoutOverlayPresented = true
        TrainApplicationLifecycle.isLiveWorkoutSetFieldEditing = true
        XCTAssertTrue(
            TrainApplicationLifecycle.shouldDeferForegroundHousekeeping(workoutPresented: true)
        )
    }

    func testShouldSkipDeferredSystemWorkDuringWorkout() {
        TrainApplicationLifecycle.isWorkoutOverlayPresented = true
        TrainApplicationLifecycle.setLastDidEnterBackgroundForTesting(Date())
        XCTAssertTrue(TrainApplicationLifecycle.shouldSkipDeferredSystemWork())
    }

    func testShouldSkipDeferredSystemWorkWhileEditing() {
        TrainApplicationLifecycle.isLiveWorkoutSetFieldEditing = true
        XCTAssertTrue(TrainApplicationLifecycle.shouldSkipDeferredSystemWork())
    }

    func testShouldNotDeferForegroundHousekeepingWithoutWorkout() {
        TrainApplicationLifecycle.setLastDidEnterBackgroundForTesting(Date())
        XCTAssertFalse(
            TrainApplicationLifecycle.shouldDeferForegroundHousekeeping(workoutPresented: false)
        )
    }

    func testShouldDeferWheneverWorkoutPresented() {
        XCTAssertTrue(
            TrainApplicationLifecycle.shouldDeferForegroundHousekeeping(workoutPresented: true)
        )
    }

    func testShouldSkipDeferredSystemWorkWheneverWorkoutOverlayUp() {
        TrainApplicationLifecycle.isWorkoutOverlayPresented = true
        XCTAssertTrue(TrainApplicationLifecycle.shouldSkipDeferredSystemWork())
    }

    func testShouldSkipDeferredSystemWorkWhileLiveSessionMinimized() {
        TrainApplicationLifecycle.isLiveWorkoutSessionInProgress = true
        XCTAssertTrue(TrainApplicationLifecycle.shouldSkipDeferredSystemWork())
    }
}
