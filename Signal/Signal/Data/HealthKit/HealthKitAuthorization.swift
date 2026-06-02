import Foundation
import HealthKit
import os

enum HealthKitAuthorization {
    static func resolveAccessState(healthStore: HKHealthStore) async -> HealthKitAccessState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        let readTypes = HealthKitTier1Kind.authorizationReadTypes
        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    Log.healthkit.error(
                        "getRequestStatusForAuthorization failed: \(String(describing: error), privacy: .public)"
                    )
                }
                let resolved: HealthKitAccessState
                switch status {
                case .shouldRequest:
                    resolved = .notDetermined
                case .unnecessary:
                    resolved = .ready
                case .unknown:
                    resolved = .notDetermined
                @unknown default:
                    resolved = .notDetermined
                }
                Log.healthkit.info(
                    "access state resolved requestStatus=\(String(describing: status), privacy: .public) access=\(String(describing: resolved), privacy: .public)"
                )
                continuation.resume(returning: resolved)
            }
        }
    }

    static func isAuthorizationDeniedError(_ error: Error) -> Bool {
        guard let hkError = error as? HKError else { return false }
        return hkError.code == .errorAuthorizationDenied
    }

    static func isAuthorizationNotDeterminedError(_ error: Error) -> Bool {
        guard let hkError = error as? HKError else { return false }
        return hkError.code == .errorAuthorizationNotDetermined
    }
}
