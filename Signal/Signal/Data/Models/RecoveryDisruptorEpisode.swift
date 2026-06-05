import Foundation
import SwiftData

enum RecoveryDisruptorKind: String, Codable, CaseIterable, Sendable {
    case alcohol
    case trainingLoad
    case sleepDebt
    case illnessLike
    case unknown
}

enum RecoveryDisruptorSource: String, Codable, Sendable {
    case userTag
    case inferred
}

@Model
final class RecoveryDisruptorEpisode {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dedupeKey: String
    var startDay: Date
    var endDay: Date?
    var kindRaw: String
    var sourceRaw: String
    var confidence: Double
    var taggedAt: Date?
    var inferredEventTitle: String?

    var kind: RecoveryDisruptorKind {
        get { RecoveryDisruptorKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    var source: RecoveryDisruptorSource {
        get { RecoveryDisruptorSource(rawValue: sourceRaw) ?? .inferred }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        startDay: Date,
        endDay: Date? = nil,
        kind: RecoveryDisruptorKind,
        source: RecoveryDisruptorSource,
        confidence: Double,
        taggedAt: Date? = nil,
        inferredEventTitle: String? = nil,
        dedupeKey: String
    ) {
        self.id = id
        self.startDay = startDay
        self.endDay = endDay
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.confidence = confidence
        self.taggedAt = taggedAt
        self.inferredEventTitle = inferredEventTitle
        self.dedupeKey = dedupeKey
    }
}

struct RecoveryDisruptorEpisodeSnapshot: Sendable, Equatable {
    let id: UUID
    let startDay: Date
    let endDay: Date?
    let kind: RecoveryDisruptorKind
    let source: RecoveryDisruptorSource
    let confidence: Double
    let taggedAt: Date?
    let inferredEventTitle: String?
    let dedupeKey: String

    init(episode: RecoveryDisruptorEpisode) {
        id = episode.id
        startDay = episode.startDay
        endDay = episode.endDay
        kind = episode.kind
        source = episode.source
        confidence = episode.confidence
        taggedAt = episode.taggedAt
        inferredEventTitle = episode.inferredEventTitle
        dedupeKey = episode.dedupeKey
    }

    init(
        id: UUID = UUID(),
        startDay: Date,
        endDay: Date? = nil,
        kind: RecoveryDisruptorKind,
        source: RecoveryDisruptorSource,
        confidence: Double,
        taggedAt: Date? = nil,
        inferredEventTitle: String? = nil,
        dedupeKey: String
    ) {
        self.id = id
        self.startDay = startDay
        self.endDay = endDay
        self.kind = kind
        self.source = source
        self.confidence = confidence
        self.taggedAt = taggedAt
        self.inferredEventTitle = inferredEventTitle
        self.dedupeKey = dedupeKey
    }
}
