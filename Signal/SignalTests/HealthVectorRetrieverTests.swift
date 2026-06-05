import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct HealthVectorRetrieverTests {
  @Test func lastWeekQueryFiltersToTemporalWindow() async throws {
    EmbeddingBackend.useDeterministicTestEmbedding = true
    defer { EmbeddingBackend.useDeterministicTestEmbedding = false }

    let container = try SignalModelContainer.make(inMemoryOnly: true)
    let context = ModelContext(container)
    let store = SwiftDataVectorStore(context: context)
    let dimensions = HealthVectorDimension.embeddingGemma
    let vector = unitVector(dimensions: dimensions, axis: 0)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12))
    )
    let inWindow = calendar.date(byAdding: .day, value: -3, to: reference)!
    let outOfWindow = calendar.date(byAdding: .day, value: -20, to: reference)!

    let inKey = Summarizer.dayKey(for: inWindow, calendar: calendar)
    let outKey = Summarizer.dayKey(for: outOfWindow, calendar: calendar)

    try store.insert(
      dayKey: inKey,
      metricKind: "daily_summary",
      summaryText: "Health day \(inKey). sleep 7h.",
      vector: vector
    )
    try store.insert(
      dayKey: outKey,
      metricKind: "daily_summary",
      summaryText: "Health day \(outKey). sleep 5h.",
      vector: vector
    )

    let results = try await HealthVectorRetriever.retrieve(
      query: "how did I sleep last week",
      k: 4,
      modelContainer: container,
      referenceDate: reference,
      calendar: calendar
    )

    #expect(results.contains { $0.contains(inKey) })
    #expect(results.allSatisfy { !$0.contains(outKey) })
  }

  private func unitVector(dimensions: Int, axis: Int) -> [Float] {
    var vector = [Float](repeating: 0, count: dimensions)
    vector[axis % dimensions] = 1
    return vector
  }
}
