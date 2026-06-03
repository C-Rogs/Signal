import Foundation

enum InsightType: String, Codable, CaseIterable, Sendable {
    case volumeBelowMEV
    case volumeAboveMRV
    case acwrOverreach
    case acwrUnderloading
    case e1RMPlateau
    case hrvSuppressed
    case sleepDeficit
    case proteinGap
    case weeklyProgressNote
}

enum InsightSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case alert
}
