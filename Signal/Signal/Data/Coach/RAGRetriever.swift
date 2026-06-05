import Foundation
import SwiftData

enum RAGRetriever {
    static func retrieve(
        query: String,
        k: Int = 4,
        boostDaysWithin: Int? = nil,
        modelContainer: ModelContainer,
        referenceDate: Date = Date(),
        calendar: Calendar = SchedulingCalendar.make()
    ) async throws -> [String] {
        _ = boostDaysWithin
        return try await HealthVectorRetriever.retrieve(
            query: query,
            k: k,
            modelContainer: modelContainer,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }
}
