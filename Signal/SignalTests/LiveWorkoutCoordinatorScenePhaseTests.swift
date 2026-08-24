import SwiftData
import SwiftUI
import XCTest
@testable import Signal

@MainActor
final class LiveWorkoutCoordinatorScenePhaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var coordinator: LiveWorkoutCoordinator!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
        context = ModelContext(container)
        coordinator = LiveWorkoutCoordinator()
        coordinator.configure(modelContext: context)
        AppLifecycleBroker.shared.configure(workoutCoordinator: coordinator)
    }

    override func tearDown() {
        AppLifecycleBroker.shared.testingIsInTrueBackground = nil
        AppLifecycleBroker.shared.isWorkoutOverlayPresented = false
        coordinator = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testInactiveDisappearDoesNotSetRemountFlag() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)

        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .inactive)

        XCTAssertFalse(coordinator.workoutBodyNeedsRemountAfterForeground)
    }

    func testBackgroundDisappearSetsRemountFlag() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)

        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)

        XCTAssertTrue(coordinator.workoutBodyNeedsRemountAfterForeground)
        XCTAssertFalse(coordinator.workoutSurfaceNeedsRefresh)
    }

    func testInactiveReturnDoesNotRemountWorkoutSurface() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(from: .active, to: .inactive)
        coordinator.handleRootScenePhaseChange(from: .inactive, to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent)
    }

    func testBackgroundReturnDoesNotRemountWithoutDisappearFlag() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(from: .active, to: .background)
        coordinator.handleRootScenePhaseChange(from: .background, to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent)
    }

    func testActiveToActiveDoesNotRefreshAgain() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(from: .active, to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent)
    }

    func testForegroundAckDoesNotBumpSurfaceGeneration() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        AppLifecycleBroker.shared.isWorkoutOverlayPresented = true
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)
    }

    func testRecoverWorkoutSurfaceAfterTrueBackgroundIsIdempotentPerGeneration() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)

        coordinator.recoverWorkoutSurfaceAfterTrueBackground()
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)

        AppLifecycleBroker.shared.isWorkoutOverlayPresented = true
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        coordinator.recoverWorkoutSurfaceAfterTrueBackground()
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)
    }

    func testConsumeWorkoutBodyRemountClearsFlag() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
        XCTAssertTrue(coordinator.workoutBodyNeedsRemountAfterForeground)

        let pending = coordinator.consumeWorkoutBodyRemountAfterForeground()

        XCTAssertTrue(pending)
        XCTAssertFalse(coordinator.workoutBodyNeedsRemountAfterForeground)
    }

    func testDisappearFlagDoesNotRemountOnBackgroundReturn() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
        let generationBeforeActive = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(from: .background, to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationBeforeActive)
    }

    func testNoRefreshWhenWorkoutNotPresented() {
        coordinator.markReadyForScenePhaseRefresh()
        coordinator.handleRootScenePhaseChange(from: .inactive, to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)
    }

    func testPresentWorkoutDoesNotBumpSurfaceGeneration() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)
    }

    func testBlankBodyDetectedRequestsRemount() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)

        coordinator.requestWorkoutSurfaceRefresh(reason: "blankBodyDetected")

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 1)
    }

    func testWatchStartTrackedPerSession() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        let sessionID = session.persistentModelID
        XCTAssertFalse(coordinator.hasStartedWatch(for: sessionID))
        coordinator.markWatchStarted(for: sessionID)
        XCTAssertTrue(coordinator.hasStartedWatch(for: sessionID))
    }

    func testPresentWorkoutSetsPresentationState() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        XCTAssertEqual(coordinator.presentedWorkoutSessionID, session.persistentModelID)
        XCTAssertTrue(coordinator.isViewingActiveWorkout)
        XCTAssertTrue(AppLifecycleBroker.shared.isWorkoutOverlayPresented)
    }

    func testMinimizeClearsPresentationState() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.minimizeWorkout()
        XCTAssertNil(coordinator.presentedWorkoutSessionID)
        XCTAssertFalse(coordinator.isViewingActiveWorkout)
        XCTAssertFalse(AppLifecycleBroker.shared.isWorkoutOverlayPresented)
        XCTAssertNotNil(coordinator.activeSession)
    }

    func testFinishClearsPresentationState() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.resetTrainNavigation(reason: "testFinish")
        XCTAssertNil(coordinator.presentedWorkoutSessionID)
        XCTAssertFalse(coordinator.isViewingActiveWorkout)
    }
}
