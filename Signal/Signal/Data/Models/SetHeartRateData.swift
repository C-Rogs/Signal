import Foundation
import SwiftData

@Model
final class SetHeartRateData {
    var setEntryID: UUID
    var sessionID: UUID
    var avgBPM: Double
    var maxBPM: Double
    var minBPM: Double
    var sampleCount: Int
    var windowStart: Date
    var windowEnd: Date
    var computedAt: Date
    var isRestInterval: Bool

    init(
        setEntryID: UUID,
        sessionID: UUID,
        avgBPM: Double,
        maxBPM: Double,
        minBPM: Double,
        sampleCount: Int,
        windowStart: Date,
        windowEnd: Date,
        computedAt: Date = .now,
        isRestInterval: Bool = false
    ) {
        self.setEntryID = setEntryID
        self.sessionID = sessionID
        self.avgBPM = avgBPM
        self.maxBPM = maxBPM
        self.minBPM = minBPM
        self.sampleCount = sampleCount
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.computedAt = computedAt
        self.isRestInterval = isRestInterval
    }
}
