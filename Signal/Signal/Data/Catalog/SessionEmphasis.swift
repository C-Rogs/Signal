import Foundation

enum SessionEmphasis: String, CaseIterable, Codable, Sendable {
    case legs
    case push
    case pull
    case upper
    case lower
    case full
    case cardio
}
