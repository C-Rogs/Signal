import Foundation

enum CoachQueryRoute: String, Sendable, CaseIterable {
    case readiness
    case workoutPrescription
    case exerciseHistory
    case nutrition
    case schedule
    case general
}

struct CoachContextScope: Sendable {
    let route: CoachQueryRoute
    let ragK: Int
    let includeActiveInsights: Bool
    let includePersonalReadiness: Bool
    let includeRecentWorkouts: Bool
    let recentWorkoutLimit: Int
    let metricsParts: DerivedMetricsParts
    let includeCalendar: Bool

    static func make(route: CoachQueryRoute, query: String, proteinBelowTarget: Bool) -> CoachContextScope {
        let mentionsDiet = CoachQueryRouter.mentionsDiet(query)
        switch route {
        case .nutrition:
            return CoachContextScope(
                route: route,
                ragK: 4,
                includeActiveInsights: true,
                includePersonalReadiness: false,
                includeRecentWorkouts: false,
                recentWorkoutLimit: 0,
                metricsParts: [.protein, .exertion, .syncFreshness],
                includeCalendar: false
            )
        case .workoutPrescription:
            var parts: DerivedMetricsParts = [.acwr, .volume, .strainDebt, .exertion, .syncFreshness]
            if mentionsDiet || proteinBelowTarget {
                parts.insert(.protein)
            }
            return CoachContextScope(
                route: route,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: parts,
                includeCalendar: false
            )
        case .readiness:
            var parts: DerivedMetricsParts = [.acwr, .strainDebt, .syncFreshness]
            if proteinBelowTarget {
                parts.insert(.protein)
            }
            return CoachContextScope(
                route: route,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 1,
                metricsParts: parts,
                includeCalendar: false
            )
        case .exerciseHistory:
            return CoachContextScope(
                route: route,
                ragK: 4,
                includeActiveInsights: false,
                includePersonalReadiness: false,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: [.syncFreshness],
                includeCalendar: false
            )
        case .schedule:
            return CoachContextScope(
                route: route,
                ragK: 0,
                includeActiveInsights: false,
                includePersonalReadiness: false,
                includeRecentWorkouts: false,
                recentWorkoutLimit: 0,
                metricsParts: [],
                includeCalendar: true
            )
        case .general:
            return CoachContextScope(
                route: route,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: [.acwr, .volume, .protein, .exertion, .strainDebt, .syncFreshness],
                includeCalendar: false
            )
        }
    }
}

struct DerivedMetricsParts: OptionSet, Sendable {
    let rawValue: UInt8

    static let acwr = DerivedMetricsParts(rawValue: 1 << 0)
    static let volume = DerivedMetricsParts(rawValue: 1 << 1)
    static let protein = DerivedMetricsParts(rawValue: 1 << 2)
    static let exertion = DerivedMetricsParts(rawValue: 1 << 3)
    static let strainDebt = DerivedMetricsParts(rawValue: 1 << 4)
    static let syncFreshness = DerivedMetricsParts(rawValue: 1 << 5)
}

enum CoachQueryRouter {
    private struct KeywordWeight {
        let keyword: String
        let weight: Int
    }

    private static let routeKeywords: [CoachQueryRoute: [KeywordWeight]] = [
        .schedule: [
            KeywordWeight(keyword: "calendar", weight: 3),
            KeywordWeight(keyword: "schedule", weight: 3),
            KeywordWeight(keyword: "meeting", weight: 2),
            KeywordWeight(keyword: "meetings", weight: 2),
            KeywordWeight(keyword: "busy day", weight: 2),
            KeywordWeight(keyword: "tomorrow", weight: 1),
            KeywordWeight(keyword: "today", weight: 1),
            KeywordWeight(keyword: "this week", weight: 1),
            KeywordWeight(keyword: "next week", weight: 1),
        ],
        .nutrition: [
            KeywordWeight(keyword: "protein", weight: 4),
            KeywordWeight(keyword: "calories", weight: 3),
            KeywordWeight(keyword: "calorie", weight: 3),
            KeywordWeight(keyword: "macro", weight: 3),
            KeywordWeight(keyword: "macros", weight: 3),
            KeywordWeight(keyword: "nutrition", weight: 3),
            KeywordWeight(keyword: "diet", weight: 3),
            KeywordWeight(keyword: "food", weight: 2),
            KeywordWeight(keyword: "eat", weight: 2),
            KeywordWeight(keyword: "eating", weight: 2),
            KeywordWeight(keyword: "carbs", weight: 2),
            KeywordWeight(keyword: "deficit", weight: 2),
            KeywordWeight(keyword: "surplus", weight: 2),
            KeywordWeight(keyword: "meal", weight: 2),
            KeywordWeight(keyword: "hitting protein", weight: 4),
        ],
        .exerciseHistory: [
            KeywordWeight(keyword: "bench", weight: 3),
            KeywordWeight(keyword: "squat", weight: 3),
            KeywordWeight(keyword: "deadlift", weight: 3),
            KeywordWeight(keyword: "press", weight: 2),
            KeywordWeight(keyword: "row", weight: 2),
            KeywordWeight(keyword: "pull-up", weight: 3),
            KeywordWeight(keyword: "pullup", weight: 3),
            KeywordWeight(keyword: "exercise", weight: 2),
            KeywordWeight(keyword: "e1rm", weight: 4),
            KeywordWeight(keyword: "1rm", weight: 4),
            KeywordWeight(keyword: "pr ", weight: 3),
            KeywordWeight(keyword: "personal record", weight: 4),
            KeywordWeight(keyword: "progressed", weight: 3),
            KeywordWeight(keyword: "progression", weight: 3),
            KeywordWeight(keyword: "last session", weight: 3),
            KeywordWeight(keyword: "last time i", weight: 3),
        ],
        .readiness: [
            KeywordWeight(keyword: "should i train", weight: 4),
            KeywordWeight(keyword: "ready to train", weight: 4),
            KeywordWeight(keyword: "readiness", weight: 4),
            KeywordWeight(keyword: "recovery", weight: 3),
            KeywordWeight(keyword: "recover", weight: 2),
            KeywordWeight(keyword: "hrv", weight: 3),
            KeywordWeight(keyword: "sleep", weight: 2),
            KeywordWeight(keyword: "tired", weight: 2),
            KeywordWeight(keyword: "fatigue", weight: 2),
            KeywordWeight(keyword: "fatigued", weight: 2),
            KeywordWeight(keyword: "rest day", weight: 3),
            KeywordWeight(keyword: "push hard", weight: 3),
            KeywordWeight(keyword: "feel good", weight: 2),
            KeywordWeight(keyword: "overtrained", weight: 3),
            KeywordWeight(keyword: "disruptor", weight: 3),
        ],
        .workoutPrescription: [
            KeywordWeight(keyword: "what should i train", weight: 5),
            KeywordWeight(keyword: "what to train", weight: 4),
            KeywordWeight(keyword: "workout today", weight: 4),
            KeywordWeight(keyword: "train today", weight: 3),
            KeywordWeight(keyword: "session today", weight: 3),
            KeywordWeight(keyword: "what to do", weight: 2),
            KeywordWeight(keyword: "program", weight: 2),
            KeywordWeight(keyword: "programming", weight: 2),
            KeywordWeight(keyword: "prescription", weight: 3),
            KeywordWeight(keyword: "focus on", weight: 2),
            KeywordWeight(keyword: "legs day", weight: 3),
            KeywordWeight(keyword: "leg day", weight: 3),
            KeywordWeight(keyword: "push day", weight: 3),
            KeywordWeight(keyword: "pull day", weight: 3),
            KeywordWeight(keyword: "upper lower", weight: 2),
            KeywordWeight(keyword: "acwr", weight: 3),
            KeywordWeight(keyword: "volume", weight: 2),
            KeywordWeight(keyword: "sets per", weight: 2),
            KeywordWeight(keyword: "working sets", weight: 2),
            KeywordWeight(keyword: "muscle group", weight: 2),
            KeywordWeight(keyword: "hypertrophy", weight: 2),
            KeywordWeight(keyword: "undertrained", weight: 2),
            KeywordWeight(keyword: "deload", weight: 2),
            KeywordWeight(keyword: "chest", weight: 1),
            KeywordWeight(keyword: "back", weight: 1),
            KeywordWeight(keyword: "legs", weight: 1),
            KeywordWeight(keyword: "shoulders", weight: 1),
            KeywordWeight(keyword: "arms", weight: 1),
        ],
    ]

    private static let tieBreakOrder: [CoachQueryRoute] = [
        .schedule,
        .nutrition,
        .exerciseHistory,
        .readiness,
        .workoutPrescription,
    ]

    nonisolated static func classify(_ query: String) -> CoachQueryRoute {
        let normalized = query.lowercased()
        var scores: [CoachQueryRoute: Int] = [:]

        for (route, keywords) in routeKeywords {
            for entry in keywords where normalized.contains(entry.keyword) {
                scores[route, default: 0] += entry.weight
            }
        }

        guard let topScore = scores.values.max(), topScore > 0 else {
            return .general
        }

        let tied = scores.filter { $0.value == topScore }.map(\.key)
        if tied.count == 1, let winner = tied.first {
            return winner
        }

        for route in tieBreakOrder where tied.contains(route) {
            return route
        }
        return tied.first ?? .general
    }

    nonisolated static func mentionsDiet(_ query: String) -> Bool {
        let normalized = query.lowercased()
        let dietKeywords = [
            "protein", "calories", "calorie", "macro", "macros", "nutrition",
            "diet", "food", "eat", "eating", "carbs", "deficit", "surplus", "meal",
        ]
        return dietKeywords.contains { normalized.contains($0) }
    }
}
