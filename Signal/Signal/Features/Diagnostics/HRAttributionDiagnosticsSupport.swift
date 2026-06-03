import Foundation
import SwiftData

struct HRAttributionDiagnosticsSnapshot: Sendable, Equatable {
    let totalRows: Int
    let fullSessionCount: Int
    let partialSessionCount: Int
}

enum HRAttributionDiagnosticsLoader {
    @MainActor
    static func load(in context: ModelContext) -> HRAttributionDiagnosticsSnapshot {
        let totalRows = (try? context.fetchCount(FetchDescriptor<SetHeartRateData>())) ?? 0
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        var fullCount = 0
        var partialCount = 0
        for session in sessions {
            guard let status = attributionStatus(for: session, in: context) else { continue }
            switch status {
            case .full:
                fullCount += 1
            case .partial:
                partialCount += 1
            case .noAttribution:
                break
            }
        }
        return HRAttributionDiagnosticsSnapshot(
            totalRows: totalRows,
            fullSessionCount: fullCount,
            partialSessionCount: partialCount
        )
    }

    private enum SessionAttributionStatus {
        case full
        case partial
        case noAttribution
    }

    @MainActor
    private static func attributionStatus(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> SessionAttributionStatus? {
        let sessionID = session.backupID ?? session.resolvedSessionID(in: context)
        let rows = (try? SetHeartRateDataStore.fetch(sessionID: sessionID, in: context)) ?? []
        let workRows = Set(rows.filter { !$0.isRestInterval }.map(\.setEntryID))
        var eligibleIDs: [UUID] = []
        for exercise in session.exercises {
            for set in exercise.sets {
                let setType = WorkoutSetType(storageValue: set.setType)
                guard setType != .warmup else { continue }
                guard set.startedAt != nil, set.completedAt != nil else { continue }
                eligibleIDs.append(set.entryID)
            }
        }
        guard !eligibleIDs.isEmpty else { return nil }
        let attributedCount = eligibleIDs.filter { workRows.contains($0) }.count
        if attributedCount == 0 {
            return .noAttribution
        }
        if attributedCount == eligibleIDs.count {
            return .full
        }
        return .partial
    }
}
