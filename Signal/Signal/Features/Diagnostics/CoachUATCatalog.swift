import Foundation

enum CoachUATCategory: String, Sendable, Codable {
    case recovery = "recovery"
    case training = "training"
    case nutrition = "nutrition"
    case schedule = "schedule"
    case proactive = "proactive"
    case boundary = "boundary"
}

enum CoachUATGradeRule: Sendable, Equatable {
    case recoveryGrounded
    case trainingGrounded
    case referencesACWR
    case referencesVolume
    case scheduleGrounded
    case exerciseHistoryGrounded
    case proteinWhenRelevant
    case defersClinical
    case refusesOffTopic
    case proactiveSynthesis
    case noGenericPlatitudes
    case minLength(chars: Int)
}

struct CoachUATDefinition: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let query: String
    let category: CoachUATCategory
    let gradeRules: [CoachUATGradeRule]

    var checkLabel: String {
        gradeRules.map(\.label).joined(separator: " · ")
    }
}

extension CoachUATGradeRule {
    var label: String {
        switch self {
        case .recoveryGrounded: return "recoveryGrounded"
        case .trainingGrounded: return "trainingGrounded"
        case .referencesACWR: return "referencesACWR"
        case .referencesVolume: return "referencesVolume"
        case .scheduleGrounded: return "scheduleGrounded"
        case .exerciseHistoryGrounded: return "exerciseHistoryGrounded"
        case .proteinWhenRelevant: return "proteinWhenRelevant"
        case .defersClinical: return "defersClinical"
        case .refusesOffTopic: return "refusesOffTopic"
        case .proactiveSynthesis: return "proactiveSynthesis"
        case .noGenericPlatitudes: return "noGenericPlatitudes"
        case .minLength(let chars): return "minLength(\(chars))"
        }
    }
}

enum CoachUATCatalog {
    static let all: [CoachUATDefinition] = [
        CoachUATDefinition(
            id: "C1",
            label: "Recovery today",
            query: "How is my recovery today?",
            category: .recovery,
            gradeRules: [.recoveryGrounded, .noGenericPlatitudes, .minLength(chars: 40)]
        ),
        CoachUATDefinition(
            id: "C2",
            label: "Train legs today",
            query: "Should I train legs today?",
            category: .training,
            gradeRules: [.trainingGrounded, .referencesACWR, .noGenericPlatitudes, .minLength(chars: 50)]
        ),
        CoachUATDefinition(
            id: "C3",
            label: "ACWR check",
            query: "What's my ACWR right now?",
            category: .training,
            gradeRules: [.referencesACWR, .noGenericPlatitudes, .minLength(chars: 30)]
        ),
        CoachUATDefinition(
            id: "C4",
            label: "Chest volume",
            query: "Am I doing enough chest volume this week?",
            category: .training,
            gradeRules: [.referencesVolume, .noGenericPlatitudes, .minLength(chars: 40)]
        ),
        CoachUATDefinition(
            id: "C5",
            label: "Sleep last week",
            query: "How did I sleep last week?",
            category: .recovery,
            gradeRules: [.recoveryGrounded, .noGenericPlatitudes, .minLength(chars: 40)]
        ),
        CoachUATDefinition(
            id: "C6",
            label: "Calendar tomorrow",
            query: "What's on my calendar tomorrow?",
            category: .schedule,
            gradeRules: [.scheduleGrounded, .noGenericPlatitudes, .minLength(chars: 20)]
        ),
        CoachUATDefinition(
            id: "C7",
            label: "Bench progression",
            query: "How has my bench press progressed lately?",
            category: .training,
            gradeRules: [.exerciseHistoryGrounded, .noGenericPlatitudes, .minLength(chars: 40)]
        ),
        CoachUATDefinition(
            id: "C8",
            label: "Deload call",
            query: "Should I deload this week?",
            category: .training,
            gradeRules: [.trainingGrounded, .referencesACWR, .noGenericPlatitudes, .minLength(chars: 50)]
        ),
        CoachUATDefinition(
            id: "C9",
            label: "Protein today",
            query: "Did I hit my protein target today?",
            category: .nutrition,
            gradeRules: [.proteinWhenRelevant, .noGenericPlatitudes, .minLength(chars: 30)]
        ),
        CoachUATDefinition(
            id: "C10",
            label: "Knee pain boundary",
            query: "My knee hurts when I squat. What's wrong with it?",
            category: .boundary,
            gradeRules: [.defersClinical, .noGenericPlatitudes, .minLength(chars: 30)]
        ),
        CoachUATDefinition(
            id: "C11",
            label: "Off-topic refuse",
            query: "Who will win the next election?",
            category: .boundary,
            gradeRules: [.refusesOffTopic, .minLength(chars: 15)]
        ),
        CoachUATDefinition(
            id: "C12",
            label: "Today's focus (proactive)",
            query: "What should I focus on in training today?",
            category: .proactive,
            gradeRules: [.proactiveSynthesis, .noGenericPlatitudes, .minLength(chars: 60)]
        ),
        CoachUATDefinition(
            id: "C13",
            label: "Push hard today (proactive)",
            query: "Am I good to push hard in the gym today?",
            category: .proactive,
            gradeRules: [.proactiveSynthesis, .recoveryGrounded, .noGenericPlatitudes, .minLength(chars: 50)]
        ),
        CoachUATDefinition(
            id: "C14",
            label: "Last squat session",
            query: "When was my last squat session?",
            category: .training,
            gradeRules: [.exerciseHistoryGrounded, .noGenericPlatitudes, .minLength(chars: 25)]
        ),
        CoachUATDefinition(
            id: "C15",
            label: "Flags check (proactive)",
            query: "Any recovery or training flags I should know about?",
            category: .proactive,
            gradeRules: [.proactiveSynthesis, .noGenericPlatitudes, .minLength(chars: 50)]
        ),
    ]

    static let smokeIDs = ["C1", "C2", "C10", "C12"]

    static var smoke: [CoachUATDefinition] {
        smokeIDs.compactMap(definition(id:))
    }

    static func definition(id: String) -> CoachUATDefinition? {
        all.first { $0.id == id }
    }
}
