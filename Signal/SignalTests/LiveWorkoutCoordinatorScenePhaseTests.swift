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
    }

    override func tearDown() {
        TrainApplicationLifecycle.testingIsInTrueBackground = nil
        coordinator = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testInactiveDisappearSetsNeedsRefresh() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)

        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .inactive)

        XCTAssertTrue(coordinator.workoutSurfaceNeedsRefresh)
    }

    func testBackgroundDisappearSetsNeedsRefresh() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)

        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)

        XCTAssertTrue(coordinator.workoutSurfaceNeedsRefresh)
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

    func testDisappearFlagRefreshesOnBackgroundReturn() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
        let generationBeforeActive = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(from: .background, to: .active)

        XCTAssertFalse(coordinator.workoutSurfaceNeedsRefresh)
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationBeforeActive + 1)
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

    func testRequestWorkoutSurfaceRefreshBumpsGeneration() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)

        coordinator.requestWorkoutSurfaceRefresh(reason: "blankBodyDetected")

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 1)
    }
}
