import Foundation

enum LiveWorkoutPhoneStopDecision: Equatable {
    case noop
    case awaitInFlight
    case performStop
}

enum LiveWorkoutPhoneStopGate {
    static func decide(hasStopInFlight: Bool, hasSession: Bool) -> LiveWorkoutPhoneStopDecision {
        if hasStopInFlight { return .awaitInFlight }
        if !hasSession { return .noop }
        return .performStop
    }
}
