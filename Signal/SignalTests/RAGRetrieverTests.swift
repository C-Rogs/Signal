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

    func testTemporalWindowViaRetrieverShim() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        let dimensions = HealthVectorDimension.embeddingGemma
        let vector = unitVector(dimensions: dimensions, axis: 0)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12))
        )
        let inWindow = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: reference))
        let outOfWindow = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: reference))
        let inKey = Summarizer.dayKey(for: inWindow, calendar: calendar)
        let outKey = Summarizer.dayKey(for: outOfWindow, calendar: calendar)

        try store.insert(dayKey: inKey, metricKind: "daily_summary", summaryText: "in-window-doc", vector: vector)
        try store.insert(dayKey: outKey, metricKind: "daily_summary", summaryText: "old-doc", vector: vector)

        let results = try await RAGRetriever.retrieve(
            query: "sleep last week",
            k: 4,
            modelContainer: container,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertTrue(results.contains { $0.contains("in-window-doc") })
        XCTAssertFalse(results.contains { $0.contains("old-doc") })
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
