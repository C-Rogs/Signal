import Foundation
import Testing
@testable import Signal

struct LiveWorkoutPhoneStopGateTests {
    @Test func noopWhenNoSessionAndNoStopInFlight() {
        #expect(LiveWorkoutPhoneStopGate.decide(hasStopInFlight: false, hasSession: false) == .noop)
    }

    @Test func performStopWhenSessionActive() {
        #expect(LiveWorkoutPhoneStopGate.decide(hasStopInFlight: false, hasSession: true) == .performStop)
    }

    @Test func awaitInFlightWhenStopAlreadyRunning() {
        #expect(LiveWorkoutPhoneStopGate.decide(hasStopInFlight: true, hasSession: true) == .awaitInFlight)
        #expect(LiveWorkoutPhoneStopGate.decide(hasStopInFlight: true, hasSession: false) == .awaitInFlight)
    }
}
