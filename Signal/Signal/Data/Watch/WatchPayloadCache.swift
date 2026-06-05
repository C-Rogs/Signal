import Foundation
#if os(watchOS)
import WatchConnectivity
#endif

enum WatchPayloadCache {
    static let appGroupIdentifier = SignalIdentifiers.appGroup
    static let payloadKey = "latestWatchPayload"
    static let iosWidgetKind = "SignalRecovery"

    @discardableResult
    static func write(context: [String: Any]) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }
        defaults.set(context, forKey: payloadKey)
        return true
    }

    static func readContext() -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let context = defaults.dictionary(forKey: payloadKey),
              !context.isEmpty
        else {
            return nil
        }
        return context
    }

    static func readPayload() -> WatchPayload? {
        guard let context = readContext() else { return nil }
        return try? WatchPayload.decode(from: context)
    }

    /// Widget timelines read the App Group. Fall back to the last WCSession context on watchOS.
    static func readPayloadHydratingFromSession() -> WatchPayload? {
        if let payload = readPayload() {
            return payload
        }
        #if os(watchOS)
        guard WCSession.isSupported() else { return nil }
        let context = WCSession.default.receivedApplicationContext
        guard !context.isEmpty, write(context: context) else { return nil }
        return try? WatchPayload.decode(from: context)
        #else
        return nil
        #endif
    }
}
