import Foundation
import SwiftData

enum DeloadSuggestionReader {
    @MainActor
    static func isDeloadActive(in context: ModelContext, calendar: Calendar = .current) -> Bool {
        if hasActiveDeloadInsight(in: context) {
            return true
        }
        let referenceDay = calendar.startOfDay(for: Date())
        let exertionContext = ExertionContextBuilder.build(
            in: context,
            referenceDay: referenceDay,
            calendar: calendar
        )
        return exertionContext.deloadSuggested
    }

    @MainActor
    static func hasActiveDeloadInsight(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        return rows.contains { insight in
            guard insight.type == .acwrDeloadSuggested else { return false }
            guard !insight.isActioned else { return false }
            guard let expires = insight.expiresAt else { return true }
            return expires > now
        }
    }
}
