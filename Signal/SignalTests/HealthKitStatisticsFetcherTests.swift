import HealthKit
import XCTest
@testable import Signal

final class HealthKitStatisticsFetcherTests: XCTestCase {
    func testIsNoDataRecognizesHKErrorCode11() {
        let error = HKError(.errorNoData)
        XCTAssertTrue(HealthKitQueryErrors.isNoData(error))
    }

    func testIsNoDataRejectsOtherErrors() {
        let error = HKError(.errorAuthorizationDenied)
        XCTAssertFalse(HealthKitQueryErrors.isNoData(error))
        XCTAssertFalse(HealthKitQueryErrors.isNoData(NSError(domain: "test", code: 11)))
    }
}
