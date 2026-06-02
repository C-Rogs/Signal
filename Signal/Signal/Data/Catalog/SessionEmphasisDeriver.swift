import Foundation

enum SessionEmphasisDeriver {
    static func emphasis(for session: WorkoutSession) -> Set<SessionEmphasis> {
        var result: Set<SessionEmphasis> = []
        var primaryMuscles: Set<Muscle> = []
        var patterns: Set<MovementPattern> = []

        for exercise in session.exercises {
            guard let catalog = exercise.catalogEntry else { continue }
            primaryMuscles.formUnion(catalog.primaryMuscles)
            patterns.insert(catalog.movementPattern)
        }

        if patterns.contains(.cardio) {
            result.insert(.cardio)
        }

        let legMuscles: Set<Muscle> = [.quads, .hamstrings, .glutes, .calves]
        let pushMuscles: Set<Muscle> = [.chest, .frontDelts, .sideDelts, .triceps]
        let pullMuscles: Set<Muscle> = [.lats, .upperBack, .rearDelts, .biceps, .traps]
        if !primaryMuscles.intersection(legMuscles).isEmpty
            || patterns.contains(.squat) || patterns.contains(.hinge) || patterns.contains(.lunge) {
            result.insert(.legs)
            result.insert(.lower)
        }
        if !primaryMuscles.intersection(pushMuscles).isEmpty
            || patterns.contains(.horizontalPush) || patterns.contains(.verticalPush) {
            result.insert(.push)
            result.insert(.upper)
        }
        if !primaryMuscles.intersection(pullMuscles).isEmpty
            || patterns.contains(.horizontalPull) || patterns.contains(.verticalPull) {
            result.insert(.pull)
            result.insert(.upper)
        }
        if primaryMuscles.contains(.fullBody) || patterns.count >= 4 {
            result.insert(.full)
        }
        if result.isEmpty, !session.exercises.isEmpty {
            result.insert(.full)
        }
        return result
    }
}
