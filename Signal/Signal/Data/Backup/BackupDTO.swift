import Foundation

enum BackupError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

struct SignalBackupFile: Codable, Sendable, Equatable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var userProfile: BackupUserProfile?
    var bodyweightLog: [BackupBodyweightEntry]
    var trainingGoal: BackupTrainingGoal?
    var workoutSessions: [BackupWorkoutSession]
    var customExercises: [BackupCustomExercise]
}

struct BackupUserProfile: Codable, Sendable, Equatable {
    var profileKey: String
    var heightCm: Double?
    var bodyweightKg: Double?
    var dateOfBirth: Date?
    var biologicalSex: String?
}

struct BackupBodyweightEntry: Codable, Sendable, Equatable {
    var date: Date
    var kg: Double
}

struct BackupTrainingGoal: Codable, Sendable, Equatable {
    var goalKey: String
    var primaryGoalRaw: String
    var weeklyTrainingDays: Int
    var targetRIR: Int
    var updatedAt: Date
    var notes: String?
}

struct BackupWorkoutSession: Codable, Sendable, Equatable {
    var id: UUID
    var title: String
    var sessionDescription: String?
    var startedAt: Date
    var finishedAt: Date?
    var date: Date
    var source: String
    var healthKitWorkoutUUID: String?
    var healthKitEffortSampleUUID: String?
    var exercises: [BackupWorkoutExercise]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sessionDescription = "description"
        case startedAt
        case finishedAt
        case date
        case source
        case healthKitWorkoutUUID
        case healthKitEffortSampleUUID
        case exercises
    }
}

struct BackupWorkoutExercise: Codable, Sendable, Equatable {
    var name: String
    var notes: String?
    var supersetId: String?
    var order: Int
    var catalogMatchFlag: String?
    var restDurationSeconds: Int
    var autoStartRestOnSetComplete: Bool
    var restTimerEndsAt: Date?
    var sets: [BackupSetEntry]
}

struct BackupSetEntry: Codable, Sendable, Equatable {
    var setIndex: Int
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var distanceKm: Double?
    var durationSeconds: Int?
    var rpe: Double?
    var prescriptionNote: String?
    var restDurationSeconds: Int?
    var isCompleted: Bool
    var hasBeenEdited: Bool
    var startedAt: Date?
    var completedAt: Date?
}

struct BackupCustomExercise: Codable, Sendable, Equatable {
    var name: String
    var aliases: [String]
    var primaryMuscleRawValues: [String]
    var secondaryMuscleRawValues: [String]
    var movementPatternRaw: String
    var equipmentRaw: String
    var isUnilateral: Bool

    var primaryMuscle: String {
        primaryMuscleRawValues.first ?? ""
    }

    var equipment: String {
        equipmentRaw
    }

    enum CodingKeys: String, CodingKey {
        case name
        case aliases
        case primaryMuscleRawValues
        case secondaryMuscleRawValues
        case movementPatternRaw
        case equipmentRaw
        case isUnilateral
        case primaryMuscle
        case equipment
    }

    init(
        name: String,
        aliases: [String],
        primaryMuscleRawValues: [String],
        secondaryMuscleRawValues: [String],
        movementPatternRaw: String,
        equipmentRaw: String,
        isUnilateral: Bool
    ) {
        self.name = name
        self.aliases = aliases
        self.primaryMuscleRawValues = primaryMuscleRawValues
        self.secondaryMuscleRawValues = secondaryMuscleRawValues
        self.movementPatternRaw = movementPatternRaw
        self.equipmentRaw = equipmentRaw
        self.isUnilateral = isUnilateral
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        movementPatternRaw = try container.decodeIfPresent(String.self, forKey: .movementPatternRaw) ?? MovementPattern.isolation.rawValue
        equipmentRaw = try container.decodeIfPresent(String.self, forKey: .equipmentRaw)
            ?? container.decodeIfPresent(String.self, forKey: .equipment)
            ?? ExerciseEquipment.other.rawValue
        isUnilateral = try container.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        secondaryMuscleRawValues = try container.decodeIfPresent([String].self, forKey: .secondaryMuscleRawValues) ?? []

        if let primaryList = try container.decodeIfPresent([String].self, forKey: .primaryMuscleRawValues), !primaryList.isEmpty {
            primaryMuscleRawValues = primaryList
        } else if let single = try container.decodeIfPresent(String.self, forKey: .primaryMuscle), !single.isEmpty {
            primaryMuscleRawValues = [single]
        } else {
            primaryMuscleRawValues = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(primaryMuscleRawValues, forKey: .primaryMuscleRawValues)
        try container.encode(secondaryMuscleRawValues, forKey: .secondaryMuscleRawValues)
        try container.encode(movementPatternRaw, forKey: .movementPatternRaw)
        try container.encode(equipmentRaw, forKey: .equipmentRaw)
        try container.encode(isUnilateral, forKey: .isUnilateral)
        try container.encode(primaryMuscle, forKey: .primaryMuscle)
        try container.encode(equipment, forKey: .equipment)
    }
}

struct BackupImportResult: Sendable, Equatable {
    var importedSessionCount: Int
    var importedBodyweightCount: Int
    var importedCustomExerciseCount: Int
}

enum BackupCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
