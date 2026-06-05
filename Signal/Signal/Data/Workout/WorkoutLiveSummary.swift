import Foundation

struct WorkoutLiveSummary: Sendable, Equatable {
    let durationSeconds: Int
    let volumeKg: Double
    let completedSetCount: Int
    let heartRateBPM: Int?

    static func compute(
        for session: WorkoutSession,
        heartRateBPM: Int? = nil,
        now: Date = .now
    ) -> WorkoutLiveSummary {
        let stats = volumeStats(for: session)
        let duration = max(0, Int(now.timeIntervalSince(session.startTime)))
        return WorkoutLiveSummary(
            durationSeconds: duration,
            volumeKg: stats.volumeKg,
            completedSetCount: stats.completedSetCount,
            heartRateBPM: heartRateBPM
        )
    }

    static func volumeStats(for session: WorkoutSession) -> (volumeKg: Double, completedSetCount: Int) {
        var volumeKg = 0.0
        var completedSets = 0

        for exercise in session.exercises {
            for set in exercise.sets where set.isCompleted {
                completedSets += 1
                guard !isWarmup(set) else { continue }
                if let weight = set.weightKg, let reps = set.reps, weight > 0, reps > 0 {
                    volumeKg += weight * Double(reps)
                }
            }
        }

        return (volumeKg, completedSets)
    }

    private static func isWarmup(_ set: SetEntry) -> Bool {
        WorkoutSetType(storageValue: set.setType) == .warmup
    }

    static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dmin %ds", minutes, secs)
        }
        return String(format: "%ds", secs)
    }
}
