import Foundation

/// Rule-based warmup suggestions for live strength work (no LLM).
/// Hypertrophy-first: early-session compound lifts get 1–2 ramp sets at submax load.
struct WarmupRecommendation: Sendable, Equatable {
    let setCount: Int
    let weightFractions: [Double]
    let reps: Int
    let summary: String
}

struct WarmupRecommendationInput: Sendable, Equatable {
    let enabled: Bool
    let mode: ExerciseLoggingMode
    let movementPattern: MovementPattern?
    let exerciseOrder: Int
    let goal: GoalType
    let anchorWeightKg: Double?
    let anchorReps: Int?
    let alreadyHasWarmupSets: Bool
}

enum WarmupRecommendationEngine {
    static func recommend(_ input: WarmupRecommendationInput) -> WarmupRecommendation? {
        guard input.enabled else { return nil }
        guard input.mode == .strength else { return nil }
        guard !input.alreadyHasWarmupSets else { return nil }
        guard let pattern = input.movementPattern else { return nil }
        guard qualifiesForSlot(order: input.exerciseOrder, pattern: pattern) else { return nil }

        let setCount = warmupSetCount(goal: input.goal, order: input.exerciseOrder, pattern: pattern)
        guard setCount > 0 else { return nil }

        let fractions = weightFractions(setCount: setCount, goal: input.goal)
        let reps = warmupReps(goal: input.goal)
        let summary = summaryText(
            setCount: setCount,
            fractions: fractions,
            anchorWeightKg: input.anchorWeightKg,
            anchorReps: input.anchorReps ?? reps,
            pattern: pattern,
            order: input.exerciseOrder
        )
        return WarmupRecommendation(
            setCount: setCount,
            weightFractions: fractions,
            reps: reps,
            summary: summary
        )
    }

    static func isCompoundLift(_ pattern: MovementPattern) -> Bool {
        switch pattern {
        case .squat, .hinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .lunge:
            true
        case .carry, .isolation, .cardio, .core:
            false
        }
    }

    static func qualifiesForSlot(order: Int, pattern: MovementPattern) -> Bool {
        guard isCompoundLift(pattern) else { return false }
        switch order {
        case 0:
            return true
        case 1:
            return isPrimaryCompound(pattern)
        case 2:
            return pattern == .squat || pattern == .hinge
        default:
            return false
        }
    }

    private static func isPrimaryCompound(_ pattern: MovementPattern) -> Bool {
        switch pattern {
        case .squat, .hinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .lunge:
            true
        case .carry, .isolation, .cardio, .core:
            false
        }
    }

    private static func warmupSetCount(goal: GoalType, order: Int, pattern: MovementPattern) -> Int {
        switch goal {
        case .hypertrophy, .generalFitness:
            if order == 0 { return isPrimaryCompound(pattern) ? 2 : 1 }
            return 1
        case .strength, .powerlifting:
            if order == 0 { return 2 }
            if order == 1, isPrimaryCompound(pattern) { return 1 }
            return 0
        }
    }

    private static func weightFractions(setCount: Int, goal: GoalType) -> [Double] {
        switch (setCount, goal) {
        case (1, _):
            return [0.5]
        case (2, .powerlifting), (2, .strength):
            return [0.4, 0.6]
        case (2, _):
            return [0.45, 0.65]
        default:
            return Array(repeating: 0.5, count: max(setCount, 1))
        }
    }

    private static func warmupReps(goal: GoalType) -> Int {
        switch goal {
        case .powerlifting, .strength:
            return 5
        case .hypertrophy, .generalFitness:
            return 8
        }
    }

    private static func summaryText(
        setCount: Int,
        fractions: [Double],
        anchorWeightKg: Double?,
        anchorReps: Int,
        pattern: MovementPattern,
        order: Int
    ) -> String {
        let position = order == 0 ? "first lift" : "early in the workout"
        let lift = patternLabel(pattern)
        if let anchorWeightKg, anchorWeightKg > 0, let topFraction = fractions.last {
            let topWeight = anchorWeightKg * topFraction
            let rounded = (topWeight * 2).rounded() / 2
            return "\(setCount) warmup \(setCount == 1 ? "set" : "sets") for this \(position) \(lift), ramping to about \(Int(rounded)) kg before working sets."
        }
        return "\(setCount) warmup \(setCount == 1 ? "set" : "sets") suggested for this \(position) \(lift) (~\(anchorReps) reps, build load gradually)."
    }

    private static func patternLabel(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .squat: "squat pattern"
        case .hinge: "hinge"
        case .horizontalPush: "press"
        case .verticalPush: "vertical press"
        case .horizontalPull: "row"
        case .verticalPull: "pull"
        case .lunge: "lunge"
        case .carry: "carry"
        case .isolation: "isolation"
        case .cardio: "cardio"
        case .core: "core"
        }
    }
}
