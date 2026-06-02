import Foundation
import SwiftData

struct MuscleVolumePoint: Sendable, Equatable {
    let muscle: Muscle
    let weeklySets: Double
}

struct MuscleHeatmapPoint: Sendable, Equatable {
    let muscle: Muscle
    let intensity: Double
}

@MainActor
enum UserMuscleVolumeService {
    static func weeklyVolumePerMuscle(
        from rangeStart: Date,
        to rangeEnd: Date,
        source: String? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [Muscle: Double] {
        let sessions = try fetchSessions(from: rangeStart, to: rangeEnd, source: source, in: context)
        var totals: [Muscle: Double] = [:]
        for session in sessions {
            let sessionVolumes = sessionMuscleVolumes(session)
            for (muscle, volume) in sessionVolumes {
                totals[muscle, default: 0] += volume
            }
        }
        return totals
    }

    static func weeklyVolumeSeries(
        from rangeStart: Date,
        to rangeEnd: Date,
        source: String? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [Date: [Muscle: Double]] {
        let sessions = try fetchSessions(from: rangeStart, to: rangeEnd, source: source, in: context)
        var byWeek: [Date: [Muscle: Double]] = [:]
        for session in sessions {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? session.date
            let sessionVolumes = sessionMuscleVolumes(session)
            var weekTotals = byWeek[weekStart, default: [:]]
            for (muscle, volume) in sessionVolumes {
                weekTotals[muscle, default: 0] += volume
            }
            byWeek[weekStart] = weekTotals
        }
        return byWeek
    }

    static func heatmapData(
        from rangeStart: Date,
        to rangeEnd: Date,
        source: String? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [MuscleHeatmapPoint] {
        let totals = try weeklyVolumePerMuscle(
            from: rangeStart,
            to: rangeEnd,
            source: source,
            in: context,
            calendar: calendar
        )
        let maxVolume = totals.values.max() ?? 0
        guard maxVolume > 0 else {
            return Muscle.allCases.map { MuscleHeatmapPoint(muscle: $0, intensity: 0) }
        }
        return Muscle.allCases.map { muscle in
            let value = totals[muscle, default: 0]
            return MuscleHeatmapPoint(muscle: muscle, intensity: value / maxVolume)
        }
    }

    private static func sessionMuscleVolumes(_ session: WorkoutSession) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for exercise in session.exercises {
            for set in exercise.sets {
                let setVolume = FractionalVolume.fractionalVolume(for: set, exercise: exercise)
                for (muscle, amount) in setVolume {
                    totals[muscle, default: 0] += amount
                }
            }
        }
        return totals
    }

    private static func fetchSessions(
        from rangeStart: Date,
        to rangeEnd: Date,
        source: String?,
        in context: ModelContext
    ) throws -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.date >= rangeStart && session.date <= rangeEnd
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let sessions = try context.fetch(descriptor)
        if let source {
            return sessions.filter { $0.source == source }
        }
        return sessions
    }
}
