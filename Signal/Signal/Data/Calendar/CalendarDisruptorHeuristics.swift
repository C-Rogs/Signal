import Foundation

enum CalendarDisruptorHeuristics {
    static let eveningWindowStartHour = 18
    static let morningWindowEndHour = 6

    static let userPhraseMatchConfidence = 0.85
    static let embeddingMatchConfidence = 0.70
    static let embeddingSimilarityThreshold: Float = 0.72
    static let fmMinimumConfidence = 0.55
    static let fmMaximumConfidence = 0.75
    static let fmShortSleepBonus = 0.10
    static let fmShortSleepBonusCap = 0.85
    static let confirmSheetMinimumConfidence = 0.55
    static let confirmSheetMaximumConfidence = 0.69
    static let silentInferMinimumConfidence = 0.70

    static let builtInSeedPhrases: [String] = [
        "pub night",
        "drinks",
        "happy hour",
        "bar",
        "wine",
        "beer",
        "cocktail",
        "night out",
        "dinner with",
    ]

    static let titleBlocklist: [String] = [
        "dentist",
        "doctor",
        "therapy",
        "physio",
        "appointment",
        "meeting",
        "standup",
        "interview",
        "flight",
        "gym",
        "workout",
        "training",
    ]

    static func calendarInferredDedupeKey(eveningStartDay: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: eveningStartDay)
        return "calendar.alcohol.\(Int(start.timeIntervalSince1970))"
    }

    static func confirmDismissKey(eveningStartDay: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: eveningStartDay)
        return "signal.recovery.calendarConfirmDismissed.\(Int(start.timeIntervalSince1970))"
    }
}
