import Foundation

struct VolumeInsightRow: Sendable, Equatable {
    let muscleGroup: MuscleGroup
    let fractionalSets: Double
    let status: VolumeStatus
    let mev: Int
    let mrv: Int
}

struct DailyMetricSample: Sendable, Equatable {
    let date: Date
    let hrvSDNN_ms: Double?
    let restingHR: Double?
    let sleepHours: Double?
    let wristTemperatureDeltaC: Double?
}

struct DailyProteinSample: Sendable, Equatable {
    let date: Date
    let proteinG: Double?
}

struct ExerciseProgressSample: Sendable, Equatable {
    let exerciseID: String
    let displayName: String
    let sessionDate: Date
    let e1RMKg: Double
}

struct WeeklyPRHighlight: Sendable, Equatable {
    let name: String
    let e1RMKg: Double
}

struct WeeklyProgressInputs: Sendable, Equatable {
    let sessionCount: Int
    let musclesCovered: [MuscleGroup]
    let topPR: WeeklyPRHighlight?
    let acwrZone: ACWRZone?
    let averageSleepHours: Double?
}

struct ReflectionSnapshot: Sendable {
    let referenceDate: Date
    let isoWeek: ISOWeekIdentifier
    let volumeRows: [VolumeInsightRow]
    let acwr: ACWRResult?
    let exerciseProgress: [ExerciseProgressSample]
    let dailyMetrics: [DailyMetricSample]
    let proteinSamples: [DailyProteinSample]
    let proteinTargetMinGrams: Double?
    let weeklyProgress: WeeklyProgressInputs
}

extension MuscleGroup {
    var insightDisplayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .quads: return "Quadriceps"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }
}
