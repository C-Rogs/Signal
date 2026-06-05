import SwiftData
import XCTest
@testable import Signal

@MainActor
final class FoundationModelsHealthDeviceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
    }

    func testFoundationModelsHealthSuiteOnDevice() async throws {
        let status = CoachModelAvailabilityFormatter.currentStatus()
        guard status.canAskCoach else {
            throw XCTSkip("Apple Intelligence not ready: \(status.label)")
        }

        let report = await FoundationModelsHealthRunner.run(modelContainer: container)

        XCTAssertFalse(report.outcomes.isEmpty, "Expected at least one probe outcome")
        XCTAssertEqual(report.outcomes.count, FoundationModelsHealthCatalog.all.count)

        for outcome in report.outcomes {
            XCTAssertFalse(outcome.probeID.isEmpty)
            XCTAssertNotEqual(outcome.verdict, .fail, "Probe \(outcome.probeID) failed: \(outcome.errorMessage ?? outcome.detail ?? "")")
        }

        XCTAssertTrue(
            FoundationModelsHealthGrader.suitePassed(report.outcomes),
            "Health suite summary: \(report.summaryLine)"
        )
    }

    func testFoundationModelsHealthReportJSONRoundTrip() async throws {
        let status = CoachModelAvailabilityFormatter.currentStatus()
        guard status.canAskCoach else {
            throw XCTSkip("Apple Intelligence not ready: \(status.label)")
        }

        let report = await FoundationModelsHealthRunner.run(
            modelContainer: container,
            definitions: Array(FoundationModelsHealthCatalog.all.prefix(2))
        )

        let json = report.jsonString
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("model_ready") || json.contains("modelStatusLabel"))

        let text = FoundationModelsHealthShareReport.build(report: report)
        XCTAssertTrue(text.contains("APPLE INTELLIGENCE HEALTH CHECK"))
    }
}
