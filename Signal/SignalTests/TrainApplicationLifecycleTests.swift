import UIKit
import XCTest
@testable import Signal

@MainActor
final class TrainApplicationLifecycleTests: XCTestCase {
    private var broker: AppLifecycleBroker!

    override func setUp() {
        super.setUp()
        broker = AppLifecycleBroker.shared
        broker.installObserversIfNeeded()
    }

    override func tearDown() {
        broker.testingIsInTrueBackground = nil
        broker.isWorkoutOverlayPresented = false
        broker.isLiveWorkoutSetFieldEditing = false
        broker.isLiveWorkoutSessionInProgress = false
        broker.setLastDidEnterBackgroundForTesting(nil)
        broker.setLastWillEnterForegroundForTesting(nil)
        super.tearDown()
    }

    func testShouldDeferForegroundHousekeepingWhenWorkoutPresentedAfterRecentBackground() {
        broker.setLastDidEnterBackgroundForTesting(Date())
        broker.isWorkoutOverlayPresented = true
        XCTAssertTrue(
            broker.shouldDeferForegroundHousekeeping(workoutPresented: false)
        )
    }

    func testShouldDeferForegroundHousekeepingWhileEditing() {
        broker.isWorkoutOverlayPresented = true
        broker.isLiveWorkoutSetFieldEditing = true
        XCTAssertTrue(
            broker.shouldDeferForegroundHousekeeping(workoutPresented: true)
        )
    }

    func testShouldSkipDeferredSystemWorkDuringWorkout() {
        broker.isWorkoutOverlayPresented = true
        broker.setLastDidEnterBackgroundForTesting(Date())
        XCTAssertTrue(broker.shouldSkipDeferredSystemWork())
    }

    func testShouldSkipDeferredSystemWorkWhileEditing() {
        broker.isLiveWorkoutSetFieldEditing = true
        XCTAssertTrue(broker.shouldSkipDeferredSystemWork())
    }

    func testShouldNotDeferForegroundHousekeepingWithoutWorkout() {
        broker.setLastDidEnterBackgroundForTesting(Date())
        XCTAssertFalse(
            broker.shouldDeferForegroundHousekeeping(workoutPresented: false)
        )
    }

    func testShouldDeferWheneverWorkoutPresented() {
        XCTAssertTrue(
            broker.shouldDeferForegroundHousekeeping(workoutPresented: true)
        )
    }

    func testShouldSkipDeferredSystemWorkWheneverWorkoutOverlayUp() {
        broker.isWorkoutOverlayPresented = true
        XCTAssertTrue(broker.shouldSkipDeferredSystemWork())
    }

    func testShouldSkipDeferredSystemWorkWhileLiveSessionMinimized() {
        broker.isLiveWorkoutSessionInProgress = true
        XCTAssertTrue(broker.shouldSkipDeferredSystemWork())
    }

    func testPathPopGraceActiveAfterForeground() {
        broker.setLastWillEnterForegroundForTesting(Date())
        XCTAssertTrue(broker.pathPopGraceActive)
        XCTAssertTrue(broker.recentlyEnteredForeground)
    }

    func testPathPopGraceInactiveAfterGraceWindow() {
        broker.setLastWillEnterForegroundForTesting(Date().addingTimeInterval(-3))
        XCTAssertFalse(broker.pathPopGraceActive)
    }

    func testBackgroundFocusDismissGenerationIncrementsOnWorkoutBackground() {
        let initial = broker.backgroundFocusDismissGeneration
        broker.isWorkoutOverlayPresented = true
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(broker.backgroundFocusDismissGeneration, initial + 1)
        XCTAssertTrue(broker.isInTrueBackground)
    }
}
