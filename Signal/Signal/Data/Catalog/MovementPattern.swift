import Foundation

enum MovementPattern: String, CaseIterable, Codable, Sendable {
    case squat
    case hinge
    case lunge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case carry
    case isolation
    case cardio
    case core
}
