import Foundation
import SwiftData
import os

enum RAGRetriever {
    static func retrieve(
        query: String,
        k: Int = 4,
        boostDaysWithin: Int? = 30,
        modelContainer: ModelContainer
    ) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, k > 0 else { return [] }

        let service = EmbeddingBackend.makeService()
        let vector = try await service.embed(trimmed, kind: .query)

        return try await MainActor.run {
            let context = ModelContext(modelContainer)
            let store = SwiftDataVectorStore(context: context)
            return try rankNeighbors(
                vector: vector,
                k: k,
                boostDaysWithin: boostDaysWithin,
                store: store
            )
        }
    }

    @MainActor
    private static func rankNeighbors(
        vector: [Float],
        k: Int,
        boostDaysWithin: Int?,
        store: any VectorStore
    ) throws -> [String] {
        let overFetch = max(k, k * 3)
        let neighbors = try store.nearestNeighbors(
            query: vector,
            k: overFetch,
            fromDayKey: nil,
            toDayKey: nil
        )

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: Date())
        let ranked = neighbors.map { neighbor -> (summaryText: String, score: Float) in
            let boost: Float
            if let boostDaysWithin,
               isDayKey(neighbor.dayKey, withinDays: boostDaysWithin, referenceDay: referenceDay, calendar: calendar) {
                boost = 1.2
            } else {
                boost = 1.0
            }
            return (neighbor.summaryText, neighbor.similarity * boost)
        }
        .sorted { $0.score > $1.score }

        let top = ranked.prefix(k).map(\.summaryText)
        Log.coach.info("RAG retrieve hits=\(top.count, privacy: .public) overFetch=\(overFetch, privacy: .public)")
        return Array(top)
    }

    private static func isDayKey(
        _ dayKey: String,
        withinDays days: Int,
        referenceDay: Date,
        calendar: Calendar
    ) -> Bool {
        guard let day = parseDayKey(dayKey, calendar: calendar) else { return false }
        guard let windowStart = calendar.date(byAdding: .day, value: -days, to: referenceDay) else {
            return false
        }
        return day >= windowStart && day <= referenceDay
    }

    private static func parseDayKey(_ dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
