import Foundation

struct DailySummary: Codable, Sendable, Equatable {
    var date: String
    var hrvSDNN: Double?
    var restingHR: Double?
    var activeEnergy: Double?
    var sleepHours: Double?
    var workoutsSummary: String?
    var recoveryScore: Double?

    init(
        date: String,
        hrvSDNN: Double? = nil,
        restingHR: Double? = nil,
        activeEnergy: Double? = nil,
        sleepHours: Double? = nil,
        workoutsSummary: String? = nil,
        recoveryScore: Double? = nil
    ) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.activeEnergy = activeEnergy
        self.sleepHours = sleepHours
        self.workoutsSummary = workoutsSummary
        self.recoveryScore = recoveryScore
    }
}
