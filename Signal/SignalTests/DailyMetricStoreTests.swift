import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct DailyMetricStoreTests {
    @Test func insertAndFetchDailyMetric() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let metric = DailyMetric(
            date: day,
            hrvSDNN_ms: 48.5,
            restingHR: 54,
            source: "unit-test"
        )
        context.insert(metric)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyMetric>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.date == day)
        #expect(fetched.first?.hrvSDNN_ms == 48.5)
        #expect(fetched.first?.restingHR == 54)
        #expect(fetched.first?.source == "unit-test")
    }
}
