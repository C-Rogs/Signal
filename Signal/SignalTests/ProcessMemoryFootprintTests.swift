import XCTest
@testable import Signal

final class ProcessMemoryFootprintTests: XCTestCase {
    func testSnapshotReportsPositiveFootprint() {
        let snapshot = ProcessMemoryFootprint.snapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertGreaterThan(snapshot?.footprintMB ?? 0, 0)
    }

    func testDiagnosticSuffixIsNotEmpty() {
        let suffix = ProcessMemoryFootprint.diagnosticSuffix()
        XCTAssertTrue(suffix.contains("footprintMB="))
        XCTAssertTrue(suffix.contains("availableMB="))
    }
}
