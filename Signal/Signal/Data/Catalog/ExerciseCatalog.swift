import Foundation
import SwiftData

@Model
final class ExerciseCatalog {
    @Attribute(.unique) var canonicalName: String
    var aliases: [String]
    var primaryMuscleRawValues: [String]
    var secondaryMuscleRawValues: [String]
    var movementPatternRaw: String
    var equipmentRaw: String
    var isUnilateral: Bool
    var isCustom: Bool

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.catalogEntry)
    var linkedExercises: [WorkoutExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \RoutineExercise.catalogEntry)
    var routineSlots: [RoutineExercise] = []

    init(
        canonicalName: String,
        aliases: [String] = [],
        primaryMuscles: [Muscle],
        secondaryMuscles: [Muscle],
        movementPattern: MovementPattern,
        equipment: ExerciseEquipment,
        isUnilateral: Bool = false,
        isCustom: Bool = false
    ) {
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.primaryMuscleRawValues = primaryMuscles.map(\.rawValue)
        self.secondaryMuscleRawValues = secondaryMuscles.map(\.rawValue)
        self.movementPatternRaw = movementPattern.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isUnilateral = isUnilateral
        self.isCustom = isCustom
    }

    var primaryMuscles: [Muscle] {
        primaryMuscleRawValues.compactMap(Muscle.init(rawValue:))
    }

    var secondaryMuscles: [Muscle] {
        secondaryMuscleRawValues.compactMap(Muscle.init(rawValue:))
    }

    var movementPattern: MovementPattern {
        MovementPattern(rawValue: movementPatternRaw) ?? .isolation
    }

    var equipment: ExerciseEquipment {
        ExerciseEquipment(rawValue: equipmentRaw) ?? .other
    }
}
