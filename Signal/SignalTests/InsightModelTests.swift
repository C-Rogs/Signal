import SwiftData
import XCTest
@testable import Signal

@MainActor
final class InsightModelTests: XCTestCase {
    func testDedupeKeyUniqueRejectsDuplicateInsert() throws {
        let container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(
            Insight(
                dedupeKey: "test.unique.key",
                type: .proteinGap,
                severity: .warning,
                bodyText: "first"
            )
        )
        try context.save()

        context.insert(
            Insight(
                dedupeKey: "test.unique.key",
                type: .proteinGap,
                severity: .warning,
                bodyText: "second"
            )
        )

        do {
            try context.save()
            let descriptor = FetchDescriptor<Insight>()
            let rows = try context.fetch(descriptor)
            XCTAssertEqual(rows.count, 1, "Unique dedupeKey must not create a second row")
        } catch {
            XCTAssertTrue(true)
        }
    }
}
