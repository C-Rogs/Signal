import Foundation

struct ExerciseE1RMHistoryRow: Sendable, Equatable {
    let exerciseID: String
    let sessionDate: Date
    let e1RMKg: Double
    let bestSetWeightKg: Double
    let bestSetReps: Int
}
