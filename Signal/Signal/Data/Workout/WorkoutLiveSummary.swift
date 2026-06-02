import Foundation

struct WorkoutLiveSummary: Sendable, Equatable {
    let durationSeconds: Int
    let volumeKg: Double
    let completedSetCount: Int

    static func compute(for session: WorkoutSession, now: Date = .now) -> WorkoutLiveSummary {
        let duration = max(0, Int(now.timeIntervalSince(session.startTime)))
        var volumeKg = 0.0
        var completedSets = 0

        for exercise in session.exercises {
            for set in exercise.sets where set.isCompleted {
                completedSets += 1
                if let weight = set.weightKg, let reps = set.reps, weight > 0, reps > 0 {
                    volumeKg += weight * Double(reps)
                }
            }
        }

        return WorkoutLiveSummary(
            durationSeconds: duration,
            volumeKg: volumeKg,
            completedSetCount: completedSets
        )
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
