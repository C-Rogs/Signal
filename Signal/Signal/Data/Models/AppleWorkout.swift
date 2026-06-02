import Foundation
import SwiftData

@Model
final class AppleWorkout {
    @Attribute(.unique) var stableID: String
    var activityType: String
    var startDate: Date
    var endDate: Date
    var durationSec: Double
    var activeEnergyKcal: Double?
    var distanceKm: Double?
    var avgRunningPowerW: Double?
    var avgStrideLengthM: Double?
    var avgVerticalOscillationCm: Double?
    var avgGroundContactMs: Double?
    var avgRunningSpeedMps: Double?
    var source: String

    init(
        stableID: String,
        activityType: String,
        startDate: Date,
        endDate: Date,
        durationSec: Double,
        activeEnergyKcal: Double? = nil,
        distanceKm: Double? = nil,
        avgRunningPowerW: Double? = nil,
        avgStrideLengthM: Double? = nil,
        avgVerticalOscillationCm: Double? = nil,
        avgGroundContactMs: Double? = nil,
        avgRunningSpeedMps: Double? = nil,
        source: String
    ) {
        self.stableID = stableID
        self.activityType = activityType
        self.startDate = startDate
        self.endDate = endDate
        self.durationSec = durationSec
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceKm = distanceKm
        self.avgRunningPowerW = avgRunningPowerW
        self.avgStrideLengthM = avgStrideLengthM
        self.avgVerticalOscillationCm = avgVerticalOscillationCm
        self.avgGroundContactMs = avgGroundContactMs
        self.avgRunningSpeedMps = avgRunningSpeedMps
        self.source = source
    }
}
