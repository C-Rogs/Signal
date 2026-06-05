import Foundation

enum CoachQueryRoute: String, Sendable, CaseIterable {
    case readiness
    case workoutPrescription
    case exerciseHistory
    case nutrition
    case schedule
    case general
}

struct CoachClassification: Sendable, Equatable {
    let route: CoachQueryRoute
    let topScore: Int
    let runnerUpRoute: CoachQueryRoute?
    let runnerUpScore: Int

    nonisolated var isCompound: Bool {
        guard runnerUpScore > 0 else { return false }
        return runnerUpScore * 10 >= topScore * 7
    }
}

struct CoachContextScope: Sendable {
    let route: CoachQueryRoute
    let secondaryRoute: CoachQueryRoute?
    let ragK: Int
    let includeActiveInsights: Bool
    let includePersonalReadiness: Bool
    let includeRecentWorkouts: Bool
    let recentWorkoutLimit: Int
    let metricsParts: DerivedMetricsParts
    let proteinPresentation: ProteinPresentation
    let includeCalendar: Bool

    static func make(
        classification: CoachClassification,
        query: String,
        proteinBelowTarget: Bool
    ) -> CoachContextScope {
        let base = baseScope(
            route: classification.route,
            query: query,
            proteinBelowTarget: proteinBelowTarget
        )
        guard classification.isCompound, let secondary = classification.runnerUpRoute else {
            return base
        }
        return base.merging(secondaryRoute: secondary, query: query, proteinBelowTarget: proteinBelowTarget)
    }

    static func legacy(query: String) -> CoachContextScope {
        let scheduleFocused = CoachQueryRouter.classify(query) == .schedule
        return CoachContextScope(
            route: .general,
            secondaryRoute: nil,
            ragK: 4,
            includeActiveInsights: true,
            includePersonalReadiness: true,
            includeRecentWorkouts: true,
            recentWorkoutLimit: 2,
            metricsParts: [.acwr, .volume, .protein, .exertion, .strainDebt, .syncFreshness],
            proteinPresentation: .deficitOnly,
            includeCalendar: scheduleFocused
        )
    }

    var filtersInsightsByRoute: Bool {
        route != .general || secondaryRoute != nil
    }

    private static func baseScope(
        route: CoachQueryRoute,
        query: String,
        proteinBelowTarget: Bool
    ) -> CoachContextScope {
        let mentionsDiet = CoachQueryRouter.mentionsDiet(query)
        switch route {
        case .nutrition:
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 4,
                includeActiveInsights: true,
                includePersonalReadiness: false,
                includeRecentWorkouts: false,
                recentWorkoutLimit: 0,
                metricsParts: [.protein, .exertion, .syncFreshness],
                proteinPresentation: .fullStatus,
                includeCalendar: false
            )
        case .workoutPrescription:
            var parts: DerivedMetricsParts = [.acwr, .volume, .strainDebt, .exertion, .syncFreshness]
            if mentionsDiet || proteinBelowTarget {
                parts.insert(.protein)
            }
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: parts,
                proteinPresentation: .deficitOnly,
                includeCalendar: false
            )
        case .readiness:
            var parts: DerivedMetricsParts = [.acwr, .strainDebt, .syncFreshness]
            if proteinBelowTarget {
                parts.insert(.protein)
            }
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 1,
                metricsParts: parts,
                proteinPresentation: .deficitOnly,
                includeCalendar: false
            )
        case .exerciseHistory:
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 4,
                includeActiveInsights: false,
                includePersonalReadiness: false,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: [.syncFreshness],
                proteinPresentation: .deficitOnly,
                includeCalendar: false
            )
        case .schedule:
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 0,
                includeActiveInsights: false,
                includePersonalReadiness: false,
                includeRecentWorkouts: false,
                recentWorkoutLimit: 0,
                metricsParts: [],
                proteinPresentation: .deficitOnly,
                includeCalendar: true
            )
        case .general:
            return CoachContextScope(
                route: route,
                secondaryRoute: nil,
                ragK: 3,
                includeActiveInsights: true,
                includePersonalReadiness: true,
                includeRecentWorkouts: true,
                recentWorkoutLimit: 2,
                metricsParts: [.acwr, .volume, .protein, .exertion, .strainDebt, .syncFreshness],
                proteinPresentation: .deficitOnly,
                includeCalendar: false
            )
        }
    }

    private func merging(
        secondaryRoute: CoachQueryRoute,
        query: String,
        proteinBelowTarget: Bool
    ) -> CoachContextScope {
        let secondary = Self.baseScope(
            route: secondaryRoute,
            query: query,
            proteinBelowTarget: proteinBelowTarget
        )
        var parts = metricsParts.union(secondary.metricsParts)
        if secondaryRoute == .nutrition || CoachQueryRouter.mentionsDiet(query) {
            parts.insert(.protein)
        }
        let presentation: ProteinPresentation = route == .nutrition || secondaryRoute == .nutrition
            ? .fullStatus
            : proteinPresentation
        return CoachContextScope(
            route: route,
            secondaryRoute: secondaryRoute,
            ragK: max(ragK, secondary.ragK),
            includeActiveInsights: includeActiveInsights || secondary.includeActiveInsights,
            includePersonalReadiness: includePersonalReadiness || secondary.includePersonalReadiness,
            includeRecentWorkouts: includeRecentWorkouts || secondary.includeRecentWorkouts,
            recentWorkoutLimit: max(recentWorkoutLimit, secondary.recentWorkoutLimit),
            metricsParts: parts,
            proteinPresentation: presentation,
            includeCalendar: includeCalendar || secondary.includeCalendar
        )
    }
}

enum ProteinPresentation: Sendable {
    case deficitOnly
    case fullStatus
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
        let requiresWordBoundary: Bool
    }

    nonisolated private static let phraseOverrides: [(phrase: String, route: CoachQueryRoute)] = [
        ("what should i train", .workoutPrescription),
        ("what to train", .workoutPrescription),
        ("what should i do in the gym", .workoutPrescription),
        ("should i train", .readiness),
        ("should i deload", .readiness),
        ("should i push hard", .readiness),
        ("am i hitting protein", .nutrition),
        ("hit my protein", .nutrition),
        ("protein target", .nutrition),
        ("what's on my calendar", .schedule),
        ("whats on my calendar", .schedule),
        ("what is on my calendar", .schedule),
        ("what's in my calendar", .schedule),
        ("whats in my calendar", .schedule),
        ("what is in my calendar", .schedule),
        ("what's my acwr", .workoutPrescription),
        ("what is my acwr", .workoutPrescription),
        ("how is my recovery", .readiness),
        ("how did i sleep", .readiness),
        ("how has my bench", .exerciseHistory),
        ("how has my squat", .exerciseHistory),
        ("how has my deadlift", .exerciseHistory),
    ]

    nonisolated private static let routeKeywords: [CoachQueryRoute: [KeywordWeight]] = [
        .schedule: [
            KeywordWeight(keyword: "calendar", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "schedule", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "meeting", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "meetings", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "busy day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "appointment", weight: 3, requiresWordBoundary: true),
        ],
        .nutrition: [
            KeywordWeight(keyword: "hitting protein", weight: 5, requiresWordBoundary: false),
            KeywordWeight(keyword: "protein target", weight: 5, requiresWordBoundary: false),
            KeywordWeight(keyword: "protein", weight: 4, requiresWordBoundary: true),
            KeywordWeight(keyword: "calories", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "calorie", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "macro", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "macros", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "nutrition", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "diet", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "food", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "carbs", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "deficit", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "surplus", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "meal", weight: 2, requiresWordBoundary: true),
        ],
        .exerciseHistory: [
            KeywordWeight(keyword: "personal record", weight: 5, requiresWordBoundary: false),
            KeywordWeight(keyword: "last session", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "last time i", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "bench press", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "bench", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "squat", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "deadlift", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "pull-up", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "pullup", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "e1rm", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "1rm", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "progressed", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "progression", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "press", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "row", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "exercise", weight: 2, requiresWordBoundary: true),
        ],
        .readiness: [
            KeywordWeight(keyword: "ready to train", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "readiness", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "recovery", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "recover", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "hrv", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "sleep", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "slept", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "tired", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "fatigue", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "fatigued", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "rest day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "push hard", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "feel good", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "overtrained", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "disruptor", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "deload", weight: 3, requiresWordBoundary: true),
        ],
        .workoutPrescription: [
            KeywordWeight(keyword: "workout today", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "train today", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "session today", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "leg day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "legs day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "push day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "pull day", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "upper lower", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "acwr", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "volume", weight: 3, requiresWordBoundary: true),
            KeywordWeight(keyword: "sets per", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "working sets", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "muscle group", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "hypertrophy", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "undertrained", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "prescription", weight: 3, requiresWordBoundary: false),
            KeywordWeight(keyword: "programming", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "program", weight: 2, requiresWordBoundary: true),
            KeywordWeight(keyword: "focus on", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "what to do", weight: 2, requiresWordBoundary: false),
            KeywordWeight(keyword: "chest volume", weight: 4, requiresWordBoundary: false),
            KeywordWeight(keyword: "enough chest", weight: 3, requiresWordBoundary: false),
        ],
    ]

    nonisolated private static let tieBreakOrder: [CoachQueryRoute] = [
        .schedule,
        .nutrition,
        .exerciseHistory,
        .readiness,
        .workoutPrescription,
    ]

    nonisolated private static let dietKeywords: [String] = [
        "protein", "calories", "calorie", "macro", "macros", "nutrition",
        "diet", "food", "carbs", "deficit", "surplus", "meal", "hitting protein",
    ]

    nonisolated static func classify(_ query: String) -> CoachQueryRoute {
        classifyDetailed(query).route
    }

    nonisolated static func classifyDetailed(_ query: String) -> CoachClassification {
        let normalized = normalize(query)

        for entry in phraseOverrides.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            if normalized.contains(entry.phrase) {
                return CoachClassification(
                    route: entry.route,
                    topScore: 100,
                    runnerUpRoute: nil,
                    runnerUpScore: 0
                )
            }
        }

        var scores: [CoachQueryRoute: Int] = [:]
        for (route, keywords) in routeKeywords {
            let sortedKeywords = keywords.sorted { $0.keyword.count > $1.keyword.count }
            for entry in sortedKeywords where matches(entry, in: normalized) {
                scores[route, default: 0] += entry.weight
            }
        }

        guard !scores.isEmpty else {
            return CoachClassification(route: .general, topScore: 0, runnerUpRoute: nil, runnerUpScore: 0)
        }

        let ranked = scores.sorted {
            if $0.value == $1.value {
                let lhsRank = tieBreakOrder.firstIndex(of: $0.key) ?? tieBreakOrder.count
                let rhsRank = tieBreakOrder.firstIndex(of: $1.key) ?? tieBreakOrder.count
                return lhsRank < rhsRank
            }
            return $0.value > $1.value
        }

        let top = ranked[0]
        guard top.value > 0 else {
            return CoachClassification(route: .general, topScore: 0, runnerUpRoute: nil, runnerUpScore: 0)
        }

        let runnerUp = ranked.count > 1 ? ranked[1] : nil
        return CoachClassification(
            route: top.key,
            topScore: top.value,
            runnerUpRoute: runnerUp?.key,
            runnerUpScore: runnerUp?.value ?? 0
        )
    }

    nonisolated static func mentionsDiet(_ query: String) -> Bool {
        let normalized = normalize(query)
        return dietKeywords.contains { keyword in
            keyword.contains(" ")
                ? normalized.contains(keyword)
                : matchesKeyword(keyword, in: normalized, requiresWordBoundary: true)
        }
    }

    nonisolated static func insightTypes(for route: CoachQueryRoute) -> Set<InsightType>? {
        switch route {
        case .nutrition:
            return [.proteinGap]
        case .readiness:
            return [
                .hrvSuppressed, .sleepDeficit, .recoveryStrain,
                .recoveryDisruptorActive, .personalReadinessLow,
            ]
        case .workoutPrescription:
            return [
                .volumeBelowMEV, .volumeAboveMRV, .acwrOverreach,
                .acwrDeloadSuggested, .acwrUnderloading, .recoveryStrain,
            ]
        case .exerciseHistory:
            return [.e1RMPlateau, .weeklyProgressNote]
        case .schedule:
            return []
        case .general:
            return nil
        }
    }

    nonisolated private static func normalize(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "what's", with: "whats")
    }

    nonisolated private static func matches(_ entry: KeywordWeight, in normalized: String) -> Bool {
        matchesKeyword(entry.keyword, in: normalized, requiresWordBoundary: entry.requiresWordBoundary)
    }

    nonisolated private static func matchesKeyword(
        _ keyword: String,
        in normalized: String,
        requiresWordBoundary: Bool
    ) -> Bool {
        if keyword.contains(" ") {
            return normalized.contains(keyword)
        }
        guard requiresWordBoundary else {
            return normalized.contains(keyword)
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![a-z])"# + NSRegularExpression.escapedPattern(for: keyword) + #"(?![a-z])"#
        ) else {
            return normalized.contains(keyword)
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.firstMatch(in: normalized, range: range) != nil
    }
}
