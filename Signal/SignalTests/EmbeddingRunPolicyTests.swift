import UIKit
import XCTest
@testable import Signal

@MainActor
final class EmbeddingRunPolicyTests: XCTestCase {
    override func tearDown() {
        EmbeddingRunPolicy.applicationDidEnterBackground()
        super.tearDown()
    }

    func testApplicationDidEnterBackgroundResumesBlockedMetalWaiters() async {
        let originalState = UIApplication.shared.applicationState
        guard originalState != .active else {
            let resumed = expectation(description: "waiter resumed on background")
            Task {
                await EmbeddingRunPolicy.waitUntilMayUseMetal()
                resumed.fulfill()
            }
            await Task.yield()
            EmbeddingRunPolicy.applicationDidEnterBackground()
            await fulfillment(of: [resumed], timeout: 1)
            return
        }
        XCTAssertFalse(EmbeddingRunPolicy.mayUseMetal)
    }
}
