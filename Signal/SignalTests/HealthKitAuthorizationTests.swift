import HealthKit
import XCTest
@testable import Signal

final class HealthKitAuthorizationTests: XCTestCase {
    func testAccessStateAfterPromptForOpaqueReadStatuses() {
        XCTAssertEqual(
            HealthKitAuthorization.accessState(for: .shouldRequest, hasPromptedForReadAccess: false),
            .notDetermined
        )
        XCTAssertEqual(
            HealthKitAuthorization.accessState(for: .shouldRequest, hasPromptedForReadAccess: true),
            .ready
        )
        XCTAssertEqual(
            HealthKitAuthorization.accessState(for: .unknown, hasPromptedForReadAccess: true),
            .ready
        )
        XCTAssertEqual(
            HealthKitAuthorization.accessState(for: .unnecessary, hasPromptedForReadAccess: false),
            .ready
        )
    }
}
