import Foundation

struct SetHeartRateDataDraft: Sendable, Equatable {
    let setEntryID: UUID
    let sessionID: UUID
    let avgBPM: Double
    let maxBPM: Double
    let minBPM: Double
    let sampleCount: Int
    let windowStart: Date
    let windowEnd: Date
    let isRestInterval: Bool
}

struct HeartRateSamplePoint: Sendable, Equatable {
    let timestamp: Date
    let bpm: Double
}

struct SetHRAttributionSetInput: Sendable, Equatable {
    let entryID: UUID
    let setIndex: Int
    let isWarmup: Bool
    let startedAt: Date?
    let completedAt: Date?
}
