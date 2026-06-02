import Foundation
import SwiftData

@Model
final class AppleWorkout {
    @Attribute(.unique) var stableID: String
    var workoutTypeName: String
    var startDate: Date
    var endDate: Date
    var durationSec: Double
    var activeEnergyKcal: Double?
    var distanceKm: Double?
    var source: String

    init(
        stableID: String,
        workoutTypeName: String,
        startDate: Date,
        endDate: Date,
        durationSec: Double,
        activeEnergyKcal: Double? = nil,
        distanceKm: Double? = nil,
        source: String
    ) {
        self.stableID = stableID
        self.workoutTypeName = workoutTypeName
        self.startDate = startDate
        self.endDate = endDate
        self.durationSec = durationSec
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceKm = distanceKm
        self.source = source
    }
}
