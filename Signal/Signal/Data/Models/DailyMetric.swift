import Foundation
import SwiftData

@Model
final class DailyMetric {
    @Attribute(.unique) var date: Date
    var hrvSDNN_ms: Double?
    var restingHR: Double?
    var activeEnergy_kcal: Double?
    var sleepHours: Double?
    var source: String

    init(
        date: Date,
        hrvSDNN_ms: Double? = nil,
        restingHR: Double? = nil,
        activeEnergy_kcal: Double? = nil,
        sleepHours: Double? = nil,
        source: String
    ) {
        self.date = date
        self.hrvSDNN_ms = hrvSDNN_ms
        self.restingHR = restingHR
        self.activeEnergy_kcal = activeEnergy_kcal
        self.sleepHours = sleepHours
        self.source = source
    }
}
