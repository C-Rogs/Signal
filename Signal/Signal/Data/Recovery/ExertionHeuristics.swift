import Foundation

enum ExertionHeuristics {
    static let hrStrainWeight = 0.6
    static let volumeWeight = 0.4
    static let hrMaxWindowDays = 30
    static let rhrWindowDays = 60
    static let debtHistoryDays = 60
    static let rollingDebtWindowDays = 7
    static let hrMaxFloor = 120.0
    static let calibrationMinHRDays = 7
    static let calibrationMinWorkouts = 5
    static let exertionDebtHighThreshold = 0.7
    static let readinessDebtPenaltyMax = 15.0
    static let deloadConsecutiveDays = 2
    static let chronicLoadWindowDays = 28
}
