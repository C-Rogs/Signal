import Foundation
import WatchConnectivity

enum LiveHeartRateSource: Equatable, Sendable {
    case watch
    case phoneHealthKit
}

struct LiveHeartRateSourceSnapshot: Sendable, Equatable {
    var isWatchConnectivitySupported: Bool
    var isSessionActivated: Bool
    var isPaired: Bool
    var isWatchAppInstalled: Bool
}

enum LiveHeartRateSourcePolicy {
    static func resolve(_ snapshot: LiveHeartRateSourceSnapshot) -> LiveHeartRateSource {
        guard snapshot.isWatchConnectivitySupported,
              snapshot.isSessionActivated,
              snapshot.isPaired,
              snapshot.isWatchAppInstalled
        else {
            return .phoneHealthKit
        }
        return .watch
    }

    static func currentFromWatchConnectivity() -> LiveHeartRateSource {
        guard WCSession.isSupported() else {
            return .phoneHealthKit
        }
        let session = WCSession.default
        return resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: true,
                isSessionActivated: session.activationState == .activated,
                isPaired: session.isPaired,
                isWatchAppInstalled: session.isWatchAppInstalled
            )
        )
    }
}
