import Foundation
import SwiftData

extension WorkoutSession {
    @MainActor
    func resolvedSessionID(in context: ModelContext) -> UUID {
        if let backupID {
            return backupID
        }
        let id = UUID()
        backupID = id
        try? context.save()
        return id
    }
}
