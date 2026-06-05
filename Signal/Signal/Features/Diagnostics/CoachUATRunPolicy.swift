import Foundation

struct CoachUATRunPolicy: Sendable, Equatable {
    let interCaseDelaySeconds: UInt64
    let maxAttempts: Int
    let retryBackoffSeconds: UInt64
    let retryOnPlatitude: Bool
    let retryOnTransientError: Bool

    static let smoke = CoachUATRunPolicy(
        interCaseDelaySeconds: 2,
        maxAttempts: 1,
        retryBackoffSeconds: 0,
        retryOnPlatitude: false,
        retryOnTransientError: false
    )

    static let full = CoachUATRunPolicy(
        interCaseDelaySeconds: 4,
        maxAttempts: 2,
        retryBackoffSeconds: 10,
        retryOnPlatitude: true,
        retryOnTransientError: true
    )
}
