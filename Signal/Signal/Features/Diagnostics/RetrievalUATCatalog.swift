import Foundation

enum RetrievalUATExpectedMode: String, Sendable {
    case windowLast7 = "window(last7)"
    case windowThisWeek = "window(thisWeek)"
    case recency
    case fuzzy
    case context

    func matches(_ mode: QueryRetrievalMode) -> Bool {
        switch (self, mode) {
        case (.windowLast7, .fixedWindow), (.windowThisWeek, .fixedWindow):
            return true
        case (.recency, .recencyRanking):
            return true
        case (.fuzzy, .pureCosine), (.context, .pureCosine):
            return true
        default:
            return false
        }
    }
}

enum RetrievalUATAutoCheck: Sendable, Equatable {
    case inParsedWindow
    case hasSleep
    case hasWorkout
    case hasNutrition
    case isRecent(days: Int)
    case proteinAboveMedian
    case sleepBelowMean30d
    case isRunning
    case hasBodyMass
    case legKeyword
    case hrvBelowMean30d
    case composite([RetrievalUATAutoCheck])

    var label: String {
        switch self {
        case .inParsedWindow:
            return "inWindow"
        case .hasSleep:
            return "hasSleep"
        case .hasWorkout:
            return "hasWorkout"
        case .hasNutrition:
            return "hasNutrition"
        case .isRecent(let days):
            return "isRecent(\(days))"
        case .proteinAboveMedian:
            return "proteinAboveMedian"
        case .sleepBelowMean30d:
            return "sleepBelowMean(30d)"
        case .isRunning:
            return "isRunning"
        case .hasBodyMass:
            return "hasBodyMass"
        case .legKeyword:
            return "legKeyword"
        case .hrvBelowMean30d:
            return "hrvBelowMean(30d)"
        case .composite(let parts):
            return parts.map(\.label).joined(separator: " AND ")
        }
    }
}

enum RetrievalUATGradeRule: Sendable, Equatable {
    case allTop3InWindowAnd(RetrievalUATAutoCheck)
    case top1RecencyLegDay
    case top1RecencyRun
    case top1LatestBodyMass
    case reviewHardLegDays
    case majoritySleepBelowMean30d
    case majorityProteinAboveMedian
    case reviewHRVBelowMean30d
    case limitHeaviestSquat
    case contextGymTonight
}

struct RetrievalUATDefinition: Identifiable, Sendable {
    let id: String
    let label: String
    let query: String
    let expectedMode: RetrievalUATExpectedMode
    let gradeRule: RetrievalUATGradeRule

    var checkLabel: String {
        switch gradeRule {
        case .allTop3InWindowAnd(let check):
            return "ALL \(check.label)"
        case .top1RecencyLegDay:
            return "top1 hasWorkout AND isRecent(45) AND legKeyword"
        case .top1RecencyRun:
            return "top1 isRunning AND isRecent(60)"
        case .top1LatestBodyMass:
            return "top1 hasBodyMass AND max-date"
        case .reviewHardLegDays:
            return "REVIEW workout+legKeyword ratios"
        case .majoritySleepBelowMean30d:
            return "majority sleepBelowMean(30d)"
        case .majorityProteinAboveMedian:
            return "majority proteinAboveMedian"
        case .reviewHRVBelowMean30d:
            return "REVIEW hrvBelowMean(30d) ratio"
        case .limitHeaviestSquat:
            return "LIMIT structured max squat"
        case .contextGymTonight:
            return "context workout14d+todayHRV"
        }
    }
}

enum RetrievalUATCatalog {
    static let all: [RetrievalUATDefinition] = [
        RetrievalUATDefinition(
            id: "T1",
            label: "Sleep last week",
            query: "how did I sleep last week",
            expectedMode: .windowLast7,
            gradeRule: .allTop3InWindowAnd(.composite([.inParsedWindow, .hasSleep]))
        ),
        RetrievalUATDefinition(
            id: "T2",
            label: "Workouts this week",
            query: "my workouts this week",
            expectedMode: .windowThisWeek,
            gradeRule: .allTop3InWindowAnd(.composite([.inParsedWindow, .hasWorkout]))
        ),
        RetrievalUATDefinition(
            id: "T3",
            label: "Nutrition last 7 days",
            query: "what did I eat in the last 7 days",
            expectedMode: .windowLast7,
            gradeRule: .allTop3InWindowAnd(.composite([.inParsedWindow, .hasNutrition]))
        ),
        RetrievalUATDefinition(
            id: "T4",
            label: "Last leg day",
            query: "when was my last leg day",
            expectedMode: .recency,
            gradeRule: .top1RecencyLegDay
        ),
        RetrievalUATDefinition(
            id: "T5",
            label: "Most recent run",
            query: "what was my most recent run",
            expectedMode: .recency,
            gradeRule: .top1RecencyRun
        ),
        RetrievalUATDefinition(
            id: "T6",
            label: "Latest weigh in",
            query: "latest weigh in",
            expectedMode: .recency,
            gradeRule: .top1LatestBodyMass
        ),
        RetrievalUATDefinition(
            id: "T7",
            label: "Hard leg days",
            query: "hard leg days",
            expectedMode: .fuzzy,
            gradeRule: .reviewHardLegDays
        ),
        RetrievalUATDefinition(
            id: "T8",
            label: "Bad sleep nights",
            query: "nights I slept badly",
            expectedMode: .fuzzy,
            gradeRule: .majoritySleepBelowMean30d
        ),
        RetrievalUATDefinition(
            id: "T9",
            label: "High protein days",
            query: "high protein days",
            expectedMode: .fuzzy,
            gradeRule: .majorityProteinAboveMedian
        ),
        RetrievalUATDefinition(
            id: "T10",
            label: "Felt run down",
            query: "days I felt run down",
            expectedMode: .fuzzy,
            gradeRule: .reviewHRVBelowMean30d
        ),
        RetrievalUATDefinition(
            id: "T11",
            label: "Heaviest squat",
            query: "my heaviest squat ever",
            expectedMode: .fuzzy,
            gradeRule: .limitHeaviestSquat
        ),
        RetrievalUATDefinition(
            id: "T12",
            label: "Gym tonight",
            query: "I am going to the gym tonight, what should I train",
            expectedMode: .context,
            gradeRule: .contextGymTonight
        ),
    ]

    static func definition(id: String) -> RetrievalUATDefinition? {
        all.first { $0.id == id }
    }
}
