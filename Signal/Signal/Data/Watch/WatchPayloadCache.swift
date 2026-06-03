import Foundation

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
}
