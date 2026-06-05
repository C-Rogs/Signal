import SwiftData
import XCTest
@testable import Signal

@MainActor
final class CoachUATDeviceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try SignalModelContainer.make(inMemoryOnly: true)
    }

    override func tearDownWithError() throws {
        EmbeddingBackend.useDeterministicTestEmbedding = false
    }

    func testCoachUATSmokeOnDevice() async throws {
        let status = CoachModelAvailabilityFormatter.currentStatus()
        guard status.canAskCoach else {
            throw XCTSkip("Apple Intelligence not ready: \(status.label)")
        }

        try await CoachUATFixtureSeeder.seed(in: container)

        let report = await CoachUATRunner.run(
            modelContainer: container,
            definitions: CoachUATCatalog.smoke,
            policy: .smoke
        )

        XCTAssertEqual(report.results.count, CoachUATCatalog.smoke.count)

        for result in report.results {
            XCTAssertNotEqual(
                result.verdict,
                .fail,
                "[\(result.definitionID)] \(result.label): \(result.notes.joined(separator: "; ")) preview=\(result.responsePreview)"
            )
            XCTAssertNotEqual(result.verdict, .limit, result.errorMessage ?? "model unavailable")
        }

        XCTAssertEqual(
            report.results.filter { $0.verdict == .fail }.count,
            0,
            "summary: \(report.summaryLine)"
        )
    }

}
