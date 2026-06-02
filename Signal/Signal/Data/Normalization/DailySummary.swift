import Foundation

struct DailySummary: Codable, Sendable, Equatable {
    var date: String
    var hrvSDNN: Double?
    var restingHR: Double?
    var activeEnergy: Double?
    var sleepHours: Double?
    var bodyMassKg: Double?
    var vo2Max: Double?
    var respiratoryRate: Double?
    var wristTemperatureDeltaC: Double?
    var bloodOxygenPct: Double?
    var heartRateMax: Double?
    var heartRateAvg: Double?
    var stepCount: Double?
    var basalEnergyKcal: Double?
    var workoutsSummary: String?
    var recoveryScore: Double?

    init(
        date: String,
        hrvSDNN: Double? = nil,
        restingHR: Double? = nil,
        activeEnergy: Double? = nil,
        sleepHours: Double? = nil,
        bodyMassKg: Double? = nil,
        vo2Max: Double? = nil,
        respiratoryRate: Double? = nil,
        wristTemperatureDeltaC: Double? = nil,
        bloodOxygenPct: Double? = nil,
        heartRateMax: Double? = nil,
        heartRateAvg: Double? = nil,
        stepCount: Double? = nil,
        basalEnergyKcal: Double? = nil,
        workoutsSummary: String? = nil,
        recoveryScore: Double? = nil
    ) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.activeEnergy = activeEnergy
        self.sleepHours = sleepHours
        self.bodyMassKg = bodyMassKg
        self.vo2Max = vo2Max
        self.respiratoryRate = respiratoryRate
        self.wristTemperatureDeltaC = wristTemperatureDeltaC
        self.bloodOxygenPct = bloodOxygenPct
        self.heartRateMax = heartRateMax
        self.heartRateAvg = heartRateAvg
        self.stepCount = stepCount
        self.basalEnergyKcal = basalEnergyKcal
        self.workoutsSummary = workoutsSummary
        self.recoveryScore = recoveryScore
    }
}
