import Foundation
import HealthKit
import os

enum HealthKitAuthorization {
    private static let didRequestReadKey = "signal.healthKit.didRequestRead"

    static var hasPromptedForReadAccess: Bool {
        UserDefaults.standard.bool(forKey: didRequestReadKey)
    }

    static func markReadAccessPrompted() {
        UserDefaults.standard.set(true, forKey: didRequestReadKey)
    }

    /// Read authorization is opaque on iOS; after the sheet is shown once, treat the app as ready to sync and infer denial from query errors.
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
                let resolved = Self.accessState(
                    for: status,
                    hasPromptedForReadAccess: hasPromptedForReadAccess
                )
                Log.healthkit.info(
                    "access state resolved requestStatus=\(String(describing: status), privacy: .public) prompted=\(hasPromptedForReadAccess, privacy: .public) access=\(String(describing: resolved), privacy: .public)"
                )
                continuation.resume(returning: resolved)
            }
        }
    }

    static func accessState(
        for requestStatus: HKAuthorizationRequestStatus,
        hasPromptedForReadAccess: Bool
    ) -> HealthKitAccessState {
        switch requestStatus {
        case .unnecessary:
            return .ready
        case .shouldRequest, .unknown:
            return hasPromptedForReadAccess ? .ready : .notDetermined
        @unknown default:
            return hasPromptedForReadAccess ? .ready : .notDetermined
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
