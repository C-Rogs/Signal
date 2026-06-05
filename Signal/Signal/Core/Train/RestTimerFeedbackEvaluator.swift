import Foundation
import SwiftData

enum RestTimerFeedbackAction: Equatable, Sendable {
    case restStarted
    case countdown(second: Int)
    case milestone(second: Int)
    case restEnded
}

struct RestTimerFeedbackState: Equatable, Sendable {
    var trackedExerciseID: String?
    var lastCountdownSecond: Int?
    var lastMilestoneSecond: Int?
    var userSkipped = false

    mutating func advance(
        activeExerciseID: String?,
        remainingSeconds: Int?
    ) -> [RestTimerFeedbackAction] {
        defer {
            if userSkipped {
                trackedExerciseID = nil
                lastCountdownSecond = nil
                lastMilestoneSecond = nil
                userSkipped = false
            } else if let activeExerciseID {
                trackedExerciseID = activeExerciseID
            } else {
                trackedExerciseID = nil
                lastCountdownSecond = nil
                lastMilestoneSecond = nil
            }
        }

        if userSkipped {
            return []
        }

        var actions: [RestTimerFeedbackAction] = []

        if let activeExerciseID, let remainingSeconds {
            if trackedExerciseID != activeExerciseID {
                actions.append(.restStarted)
                lastCountdownSecond = nil
                lastMilestoneSecond = nil
            }
            if remainingSeconds == 30 || remainingSeconds == 10,
               lastMilestoneSecond != remainingSeconds
            {
                actions.append(.milestone(second: remainingSeconds))
                lastMilestoneSecond = remainingSeconds
            }
            if remainingSeconds == 0, lastCountdownSecond != 0 {
                actions.append(.countdown(second: 0))
                lastCountdownSecond = 0
            } else if (1 ... 3).contains(remainingSeconds),
                      lastCountdownSecond != remainingSeconds
            {
                actions.append(.countdown(second: remainingSeconds))
                lastCountdownSecond = remainingSeconds
            }
            return actions
        }

        if trackedExerciseID != nil {
            actions.append(.restEnded)
        }
        return actions
    }

    mutating func markUserSkipped() {
        userSkipped = true
    }

    mutating func acknowledgeRestStarted(exerciseID: String) {
        trackedExerciseID = exerciseID
        lastCountdownSecond = nil
        lastMilestoneSecond = nil
        userSkipped = false
    }
}

enum RestTimerFeedbackEvaluator {
    static func exerciseID(for exercise: WorkoutExercise) -> String {
        String(describing: exercise.persistentModelID)
    }
}
