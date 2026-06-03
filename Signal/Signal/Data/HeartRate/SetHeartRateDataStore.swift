import Foundation
import SwiftData

@MainActor
enum SetHeartRateDataStore {
    static func fetch(sessionID: UUID, in context: ModelContext) throws -> [SetHeartRateData] {
        let descriptor = FetchDescriptor<SetHeartRateData>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        return try context.fetch(descriptor)
    }

    static func fetch(
        setEntryID: UUID,
        isRestInterval: Bool,
        in context: ModelContext
    ) throws -> SetHeartRateData? {
        let restFlag = isRestInterval
        var descriptor = FetchDescriptor<SetHeartRateData>(
            predicate: #Predicate { row in
                row.setEntryID == setEntryID && row.isRestInterval == restFlag
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func upsert(_ drafts: [SetHeartRateDataDraft], in context: ModelContext) throws {
        let computedAt = Date.now
        for draft in drafts {
            let restFlag = draft.isRestInterval
            let setID = draft.setEntryID
            var descriptor = FetchDescriptor<SetHeartRateData>(
                predicate: #Predicate { row in
                    row.setEntryID == setID && row.isRestInterval == restFlag
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.sessionID = draft.sessionID
                existing.avgBPM = draft.avgBPM
                existing.maxBPM = draft.maxBPM
                existing.minBPM = draft.minBPM
                existing.sampleCount = draft.sampleCount
                existing.windowStart = draft.windowStart
                existing.windowEnd = draft.windowEnd
                existing.computedAt = computedAt
            } else {
                context.insert(
                    SetHeartRateData(
                        setEntryID: draft.setEntryID,
                        sessionID: draft.sessionID,
                        avgBPM: draft.avgBPM,
                        maxBPM: draft.maxBPM,
                        minBPM: draft.minBPM,
                        sampleCount: draft.sampleCount,
                        windowStart: draft.windowStart,
                        windowEnd: draft.windowEnd,
                        computedAt: computedAt,
                        isRestInterval: draft.isRestInterval
                    )
                )
            }
        }
        try context.save()
    }
}
