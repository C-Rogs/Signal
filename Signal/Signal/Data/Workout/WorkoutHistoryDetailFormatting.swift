import Foundation

enum WorkoutHistoryDetailFormatting {
    static func strengthLoadLine(
        weightLabel: String,
        reps: Int?,
        rpe: Double?,
        setType: WorkoutSetType
    ) -> String {
        let repsText = reps.map(String.init) ?? "—"
        var line = "\(weightLabel) × \(repsText)"
        if let suffix = rpeSuffix(rpe: rpe, setType: setType) {
            line += suffix
        }
        return line
    }

    static func cardioLoadLine(
        distanceLabel: String,
        durationLabel: String,
        rpe: Double?,
        setType: WorkoutSetType
    ) -> String {
        var line = "\(distanceLabel) / \(durationLabel)"
        if let suffix = rpeSuffix(rpe: rpe, setType: setType) {
            line += suffix
        }
        return line
    }

    static func rpeSuffix(rpe: Double?, setType: WorkoutSetType) -> String? {
        guard setType != .warmup, let rpe else { return nil }
        return " · RPE \(WorkoutRPEScale.compactLabel(for: rpe))"
    }

    static func meanWorkingSetRPE(sets: [SetEntry]) -> Double? {
        let values = sets.compactMap { set -> Double? in
            guard WorkoutSetType(storageValue: set.setType) != .warmup,
                  let rpe = set.rpe else { return nil }
            return rpe
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func meanRPELabel(for mean: Double) -> String {
        WorkoutRPEScale.compactLabel(for: WorkoutRPEScale.snapToPicker(mean))
    }
}
