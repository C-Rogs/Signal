import Foundation
import SwiftData

@Model
final class Insight {
    var id: UUID
    @Attribute(.unique) var dedupeKey: String
    var typeRaw: String
    var severityRaw: String
    var bodyText: String
    var relatedEntity: String?
    var createdAt: Date
    var expiresAt: Date?
    var isActioned: Bool

    var type: InsightType {
        get { InsightType(rawValue: typeRaw) ?? .weeklyProgressNote }
        set { typeRaw = newValue.rawValue }
    }

    var severity: InsightSeverity {
        get { InsightSeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        dedupeKey: String,
        type: InsightType,
        severity: InsightSeverity,
        bodyText: String,
        relatedEntity: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        isActioned: Bool = false
    ) {
        self.id = id
        self.dedupeKey = dedupeKey
        self.typeRaw = type.rawValue
        self.severityRaw = severity.rawValue
        self.bodyText = bodyText
        self.relatedEntity = relatedEntity
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.isActioned = isActioned
    }
}
