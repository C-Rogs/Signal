import SwiftData
import XCTest
@testable import Signal

@MainActor
final class RAGRetrieverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EmbeddingBackend.useDeterministicTestEmbedding = true
    }

    override func tearDown() {
        EmbeddingBackend.useDeterministicTestEmbedding = false
        super.tearDown()
    }

    func testRecencyBoostPrefersRecentEquallySimilarNeighbor() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        let dimensions = HealthVectorDimension.embeddingGemma
        let vector = unitVector(dimensions: dimensions, axis: 0)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recentKey = Summarizer.dayKey(for: today, calendar: calendar)
        let oldDate = calendar.date(byAdding: .day, value: -60, to: today)!
        let oldKey = Summarizer.dayKey(for: oldDate, calendar: calendar)

        try store.insert(dayKey: recentKey, metricKind: "daily_summary", summaryText: "recent-doc", vector: vector)
        try store.insert(dayKey: oldKey, metricKind: "daily_summary", summaryText: "old-doc", vector: vector)

        let results = try await RAGRetriever.retrieve(
            query: "recovery sleep HRV",
            k: 1,
            boostDaysWithin: 30,
            modelContainer: container
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, "recent-doc")
    }

    func testRetrieveReturnsAtMostK() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        let dimensions = HealthVectorDimension.embeddingGemma

        for axis in 0 ..< 6 {
            let vector = unitVector(dimensions: dimensions, axis: axis)
            try store.insert(
                dayKey: "2026-05-\(10 + axis)",
                metricKind: "daily_summary",
                summaryText: "doc-\(axis)",
                vector: vector
            )
        }

        let k = 2
        let neighbors = try store.nearestNeighbors(
            query: unitVector(dimensions: dimensions, axis: 0),
            k: k * 3,
            fromDayKey: nil,
            toDayKey: nil
        )
        XCTAssertGreaterThanOrEqual(neighbors.count, k)

        let results = try await RAGRetriever.retrieve(
            query: "probe",
            k: k,
            boostDaysWithin: nil,
            modelContainer: container
        )
        XCTAssertLessThanOrEqual(results.count, k)
    }

    private func unitVector(dimensions: Int, axis: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        vector[axis % dimensions] = 1
        return vector
    }
}
