import Foundation
import SwiftData

@Model
final class DailyNutrition {
    @Attribute(.unique) var date: Date
    var dietaryEnergyKcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatTotalG: Double?
    var fatSaturatedG: Double?
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    var source: String

    init(
        date: Date,
        dietaryEnergyKcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatTotalG: Double? = nil,
        fatSaturatedG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        source: String
    ) {
        self.date = date
        self.dietaryEnergyKcal = dietaryEnergyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatTotalG = fatTotalG
        self.fatSaturatedG = fatSaturatedG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.source = source
    }
}
