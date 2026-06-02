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
    var bodyFatPercentage: Double?
    var leanBodyMassKg: Double?
    var walkingHeartRateAvg: Double?
    var appleExerciseMinutes: Double?
    var appleStandHours: Double?
    var physicalEffort: Double?
    var timeInDaylightMin: Double?
    var sleepingBreathingDisturbances: Double?
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var dietaryEnergyKcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatTotalG: Double?
    var fatSaturatedG: Double?
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    var workoutsSummary: String?
    var appleWorkoutsSummary: String?
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
        bodyFatPercentage: Double? = nil,
        leanBodyMassKg: Double? = nil,
        walkingHeartRateAvg: Double? = nil,
        appleExerciseMinutes: Double? = nil,
        appleStandHours: Double? = nil,
        physicalEffort: Double? = nil,
        timeInDaylightMin: Double? = nil,
        sleepingBreathingDisturbances: Double? = nil,
        bloodPressureSystolic: Double? = nil,
        bloodPressureDiastolic: Double? = nil,
        dietaryEnergyKcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatTotalG: Double? = nil,
        fatSaturatedG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        workoutsSummary: String? = nil,
        appleWorkoutsSummary: String? = nil,
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
        self.bodyFatPercentage = bodyFatPercentage
        self.leanBodyMassKg = leanBodyMassKg
        self.walkingHeartRateAvg = walkingHeartRateAvg
        self.appleExerciseMinutes = appleExerciseMinutes
        self.appleStandHours = appleStandHours
        self.physicalEffort = physicalEffort
        self.timeInDaylightMin = timeInDaylightMin
        self.sleepingBreathingDisturbances = sleepingBreathingDisturbances
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.dietaryEnergyKcal = dietaryEnergyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatTotalG = fatTotalG
        self.fatSaturatedG = fatSaturatedG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.workoutsSummary = workoutsSummary
        self.appleWorkoutsSummary = appleWorkoutsSummary
        self.recoveryScore = recoveryScore
    }
}
