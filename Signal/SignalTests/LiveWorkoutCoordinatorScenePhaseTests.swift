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

    func testInactiveReturnRefreshesPresentedWorkoutSurface() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(to: .inactive)
        coordinator.handleRootScenePhaseChange(to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent + 1)
        XCTAssertFalse(coordinator.workoutSurfaceNeedsRefresh)
    }

    func testBackgroundReturnRefreshesPresentedWorkoutSurface() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(to: .background)
        coordinator.handleRootScenePhaseChange(to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent + 1)
    }

    func testActiveToActiveDoesNotRefreshAgain() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent)
    }

    func testDisappearFlagRefreshesOnceOnActive() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        coordinator.handleRootScenePhaseChange(to: .background)
        coordinator.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
        let generationBeforeActive = coordinator.workoutSurfaceGeneration
        coordinator.markReadyForScenePhaseRefresh()

        coordinator.handleRootScenePhaseChange(to: .active)

        XCTAssertTrue(coordinator.workoutSurfaceNeedsRefresh == false)
        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationBeforeActive + 1)
    }

    func testNoRefreshWhenWorkoutNotPresented() {
        coordinator.markReadyForScenePhaseRefresh()
        coordinator.handleRootScenePhaseChange(to: .inactive)
        coordinator.handleRootScenePhaseChange(to: .active)

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, 0)
    }

    func testRequestWorkoutSurfaceRefreshBumpsGeneration() throws {
        let session = try LiveWorkoutStore(context: context).startEmpty()
        coordinator.presentWorkout(sessionID: session.persistentModelID)
        let generationAfterPresent = coordinator.workoutSurfaceGeneration

        coordinator.requestWorkoutSurfaceRefresh(reason: "blankBodyDetected")

        XCTAssertEqual(coordinator.workoutSurfaceGeneration, generationAfterPresent + 1)
    }
}
