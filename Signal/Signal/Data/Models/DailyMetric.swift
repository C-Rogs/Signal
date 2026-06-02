import Foundation
import SwiftData

@Model
final class DailyMetric {
    @Attribute(.unique) var date: Date
    var hrvSDNN_ms: Double?
    var restingHR: Double?
    var activeEnergy_kcal: Double?
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
    var source: String

    init(
        date: Date,
        hrvSDNN_ms: Double? = nil,
        restingHR: Double? = nil,
        activeEnergy_kcal: Double? = nil,
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
        source: String
    ) {
        self.date = date
        self.hrvSDNN_ms = hrvSDNN_ms
        self.restingHR = restingHR
        self.activeEnergy_kcal = activeEnergy_kcal
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
        self.source = source
    }
}
