import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ExerciseCatalogCuratorTests: XCTestCase {
    func testApplyPickerDefaultsMarksReasonableSubset() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExerciseCatalogCuratorTests-\(UUID().uuidString).sqlite")
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(for: SignalModelContainer.schema, configurations: [configuration])
        let context = ModelContext(container)

        _ = try ExerciseCatalogSeeder.seedIfNeeded(in: context)
        try ExerciseCatalogCurator.applyPickerDefaults(in: context)

        let defaults = try context.fetch(
            FetchDescriptor<ExerciseCatalog>(predicate: #Predicate { $0.isPickerDefault })
        )
        XCTAssertGreaterThanOrEqual(defaults.count, 120)
        XCTAssertLessThanOrEqual(defaults.count, 280)
    }
}
