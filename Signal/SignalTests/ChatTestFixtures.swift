import Foundation
@testable import Signal

enum ChatTestFixtures {
    nonisolated static let minimalContext = CoachContext(
        userSummary: "test",
        activeInsights: [],
        derivedMetricsSummary: "",
        ragSummaries: [],
        recentWorkouts: []
    )

    nonisolated static func singleChunkStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }
}
