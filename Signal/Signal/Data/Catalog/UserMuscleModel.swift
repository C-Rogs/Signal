import Foundation
import SwiftData

struct UserMuscleModel: Sendable {
    let weeklyVolumeByMuscle: [Muscle: Double]
    let heatmap: [MuscleHeatmapPoint]

    @MainActor
    static func compute(
        from rangeStart: Date,
        to rangeEnd: Date,
        source: String? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> UserMuscleModel {
        let weekly = try UserMuscleVolumeService.weeklyVolumePerMuscle(
            from: rangeStart,
            to: rangeEnd,
            source: source,
            in: context,
            calendar: calendar
        )
        let heatmap = try UserMuscleVolumeService.heatmapData(
            from: rangeStart,
            to: rangeEnd,
            source: source,
            in: context,
            calendar: calendar
        )
        return UserMuscleModel(weeklyVolumeByMuscle: weekly, heatmap: heatmap)
    }
}
