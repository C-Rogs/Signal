import Foundation

struct InsightSpec: Sendable, Equatable {
    let dedupeKey: String
    let type: InsightType
    let severity: InsightSeverity
    let bodyText: String
    let relatedEntity: String?
    let expiresAt: Date?
}
