import Foundation
import SwiftData

@Model
final class RecoverySnapshot {
    var date: Date
    var recoveryScore: Double
    var hrvBaseline: Double
    var hrvAcute: Double
    var notes: String?

    init(
        date: Date,
        recoveryScore: Double,
        hrvBaseline: Double,
        hrvAcute: Double,
        notes: String? = nil
    ) {
        self.date = date
        self.recoveryScore = recoveryScore
        self.hrvBaseline = hrvBaseline
        self.hrvAcute = hrvAcute
        self.notes = notes
    }
}
