import SwiftData
import XCTest
@testable import Signal

@MainActor
final class SystemWorkCoordinatorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        await SystemWorkCoordinator.shared.setTestingStepDelayForTesting(nil)
        AppLifecycleBroker.shared.testingIsInTrueBackground = nil
        AppLifecycleBroker.shared.isWorkoutOverlayPresented = false
        AppLifecycleBroker.shared.isLiveWorkoutSetFieldEditing = false
    }

    func testHealthKitDeltaSequencesStepsInOrder() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        let coordinator = SystemWorkCoordinator.shared
        let span = DateInterval(start: Date().addingTimeInterval(-3600), duration: 1800)

        await coordinator.processHealthKitDeltaForTesting(
            modelContainer: container,
            heartRateSpan: span
        )

        let steps = await coordinator.testingPipelineSteps()
        XCTAssertEqual(
            steps,
            [.invalidateMetrics, .hrAttribution, .reflection, .watchPush]
        )
    }

    func testHealthKitDeltaSkipsHRAttributionWithoutSpan() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        let coordinator = SystemWorkCoordinator.shared

        await coordinator.processHealthKitDeltaForTesting(
            modelContainer: container,
            heartRateSpan: nil
        )

        let steps = await coordinator.testingPipelineSteps()
        XCTAssertEqual(
            steps,
            [.invalidateMetrics, .reflection, .watchPush]
        )
    }

    func testDebounceSkipsDuplicateReflectionWithin60Seconds() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        let coordinator = SystemWorkCoordinator.shared
        let context = ModelContext(container)

        _ = await ReflectionEngine.shared.runReflection(in: context)
        let mayStartAfterRun = await ReflectionEngine.shared.mayStartReflection()
        XCTAssertFalse(mayStartAfterRun)

        await coordinator.processHealthKitDeltaForTesting(
            modelContainer: container,
            heartRateSpan: nil
        )

        let steps = await coordinator.testingPipelineSteps()
        XCTAssertEqual(steps, [.invalidateMetrics, .watchPush])
    }

    func testBackgroundCancelsInFlightWork() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        let coordinator = SystemWorkCoordinator.shared
        await coordinator.setTestingStepDelayForTesting(.milliseconds(200))

        let pipeline = Task {
            await coordinator.processHealthKitDeltaForTesting(
                modelContainer: container,
                heartRateSpan: nil
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        await coordinator.cancelInFlightWorkForTesting()
        await pipeline.value

        let steps = await coordinator.testingPipelineSteps()
        XCTAssertEqual(steps, [.invalidateMetrics])
        await coordinator.setTestingStepDelayForTesting(nil)
    }

    func testMayStartReflectionAllowsWhenIdle() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        let mayStart = await ReflectionEngine.shared.mayStartReflection()
        XCTAssertTrue(mayStart)
    }

    func testMayStartReflectionBlocksImmediatelyAfterRun() async throws {
        await ReflectionEngine.shared.resetReflectionStateForTesting()
        _ = await ReflectionEngine.shared.runReflection(in: ModelContext(container))
        let mayStart = await ReflectionEngine.shared.mayStartReflection()
        XCTAssertFalse(mayStart)
    }
}
